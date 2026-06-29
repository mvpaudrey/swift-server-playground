# Tournament Switch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create two scripts — `switch-tournament.sh` (patches `INIT_LEAGUES` in the ECS task definition and triggers a rolling deploy) and `verify-tournament.sh` (confirms the live server is serving the expected tournament) — so any future tournament can be activated in ~5 minutes with a single command.

**Architecture:** Both scripts read CloudFormation stack outputs to discover live resource names (cluster, service, HTTP endpoint), so they work for any environment (`staging` / `production`) without hardcoding ARNs. The switch script patches `INIT_LEAGUES` in the existing task definition JSON via `jq`, registers a new revision, updates the ECS service, and waits for stability. The verify script hits the REST API to confirm league and season.

**Tech Stack:** Bash, AWS CLI v2, `jq`, existing CloudFormation stack (`afcon-${ENV}`)

## Global Constraints

- AWS region: `eu-north-1` (default; overridable via `AWS_REGION` env var)
- CloudFormation stack name pattern: `afcon-${ENV}` (e.g. `afcon-production`)
- ECS cluster output key: `ECSClusterName`
- ECS service output key: `ECSServiceName`
- HTTP endpoint output key: `HTTPEndpoint`
- gRPC endpoint output key: `GRPCEndpoint`
- `INIT_LEAGUES` format: `"<leagueId>:<season>:<name>"` (e.g. `"1:2026:FIFA World Cup 2026"`)
- WC league ID: `1`, season: `2026`
- AFCON league ID: `6`, season: `2025`
- Scripts must follow the existing color/helper pattern from `infrastructure/update-secrets.sh`
- Scripts must support `--dry-run` flag (print what would happen, make no AWS changes)
- No hardcoded ARNs or account IDs — always resolve from stack outputs or AWS CLI

---

## File Map

```
infrastructure/
├── switch-tournament.sh    NEW — patches INIT_LEAGUES + rolling ECS deploy
└── verify-tournament.sh    NEW — hits /health and /api/league to confirm tournament
```

---

## Task 1: `switch-tournament.sh`

**Files:**
- Create: `infrastructure/switch-tournament.sh`

**Interfaces:**
- Consumes: CloudFormation stack outputs `ECSClusterName`, `ECSServiceName`; existing ECS task definition via `aws ecs describe-task-definition`
- Produces: new ECS task definition revision with updated `INIT_LEAGUES`; updated ECS service pointing at that revision

- [ ] **Step 1: Create the file with shebang, color helpers, and arg parsing**

Create `infrastructure/switch-tournament.sh`:

```bash
#!/bin/bash
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

print_header()  { echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n  $1\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }
print_info()    { echo -e "${BLUE}ℹ${NC}  $1"; }
print_success() { echo -e "${GREEN}✓${NC}  $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC}  $1"; }
print_error()   { echo -e "${RED}✗${NC}  $1"; }

# ── Defaults ──────────────────────────────────────────────────────────────────
AWS_REGION="${AWS_REGION:-eu-north-1}"
ENVIRONMENT="production"
LEAGUE_ID=""
SEASON=""
TOURNAMENT_NAME=""
DRY_RUN=false

# ── Arg parsing ───────────────────────────────────────────────────────────────
usage() {
    echo "Usage: $0 --league-id <id> --season <year> --name <name> [--environment <env>] [--dry-run]"
    echo ""
    echo "  --league-id     API-Football league ID (e.g. 1 for FIFA WC, 6 for AFCON)"
    echo "  --season        Season year (e.g. 2026)"
    echo "  --name          Human-readable name (e.g. 'FIFA World Cup 2026')"
    echo "  --environment   CloudFormation env prefix: production|staging  (default: production)"
    echo "  --dry-run       Print what would change without making AWS calls"
    echo ""
    echo "Examples:"
    echo "  $0 --league-id 1 --season 2026 --name 'FIFA World Cup 2026'"
    echo "  $0 --league-id 6 --season 2025 --name 'AFCON 2025' --environment staging"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --league-id)   LEAGUE_ID="$2";       shift 2 ;;
        --season)      SEASON="$2";           shift 2 ;;
        --name)        TOURNAMENT_NAME="$2";  shift 2 ;;
        --environment) ENVIRONMENT="$2";      shift 2 ;;
        --dry-run)     DRY_RUN=true;          shift   ;;
        --help|-h)     usage ;;
        *) print_error "Unknown argument: $1"; usage ;;
    esac
done

[[ -z "$LEAGUE_ID" || -z "$SEASON" || -z "$TOURNAMENT_NAME" ]] && {
    print_error "--league-id, --season, and --name are required"
    usage
}

[[ "$ENVIRONMENT" =~ ^(production|staging)$ ]] || {
    print_error "Invalid environment '$ENVIRONMENT'. Must be production or staging."
    exit 1
}

STACK_NAME="afcon-${ENVIRONMENT}"
INIT_LEAGUES_VALUE="${LEAGUE_ID}:${SEASON}:${TOURNAMENT_NAME}"
```

- [ ] **Step 2: Add prerequisite checks**

Append to `infrastructure/switch-tournament.sh`:

```bash
# ── Prerequisites ─────────────────────────────────────────────────────────────
check_prerequisites() {
    print_header "Checking Prerequisites"

    command -v aws  &>/dev/null || { print_error "AWS CLI not installed"; exit 1; }
    print_success "AWS CLI found: $(aws --version 2>&1 | head -1)"

    command -v jq   &>/dev/null || { print_error "jq not installed. Run: brew install jq"; exit 1; }
    print_success "jq found: $(jq --version)"

    aws sts get-caller-identity --region "$AWS_REGION" &>/dev/null || {
        print_error "AWS credentials not configured. Run: aws configure"
        exit 1
    }
    print_success "AWS credentials valid (region: ${AWS_REGION})"
}
```

- [ ] **Step 3: Add stack output resolver**

Append to `infrastructure/switch-tournament.sh`:

```bash
# ── Stack output resolver ─────────────────────────────────────────────────────
get_stack_output() {
    local KEY="$1"
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$AWS_REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='${KEY}'].OutputValue" \
        --output text 2>/dev/null
}

resolve_resources() {
    print_header "Resolving AWS Resources"

    CLUSTER_NAME=$(get_stack_output "ECSClusterName")
    SERVICE_NAME=$(get_stack_output "ECSServiceName")

    [[ -z "$CLUSTER_NAME" ]] && { print_error "Stack '${STACK_NAME}' not found or missing ECSClusterName output"; exit 1; }
    [[ -z "$SERVICE_NAME" ]] && { print_error "Stack '${STACK_NAME}' missing ECSServiceName output"; exit 1; }

    print_success "ECS Cluster: ${CLUSTER_NAME}"
    print_success "ECS Service: ${SERVICE_NAME}"
}
```

- [ ] **Step 4: Add task definition patcher**

Append to `infrastructure/switch-tournament.sh`:

```bash
# ── Task definition patcher ───────────────────────────────────────────────────
patch_and_register_task_def() {
    print_header "Patching Task Definition"

    # Get current task definition ARN from the service
    CURRENT_TASK_DEF_ARN=$(aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "$SERVICE_NAME" \
        --region "$AWS_REGION" \
        --query 'services[0].taskDefinition' \
        --output text)

    print_info "Current task definition: ${CURRENT_TASK_DEF_ARN}"

    # Fetch the full task definition JSON
    TASK_DEF_JSON=$(aws ecs describe-task-definition \
        --task-definition "$CURRENT_TASK_DEF_ARN" \
        --region "$AWS_REGION" \
        --query 'taskDefinition' \
        --output json)

    # Show current INIT_LEAGUES value
    CURRENT_LEAGUES=$(echo "$TASK_DEF_JSON" | jq -r \
        '.containerDefinitions[0].environment[] | select(.name == "INIT_LEAGUES") | .value')
    print_info "Current INIT_LEAGUES: ${CURRENT_LEAGUES}"
    print_info "New     INIT_LEAGUES: ${INIT_LEAGUES_VALUE}"

    # Patch INIT_LEAGUES in the container environment, strip read-only fields
    PATCHED_TASK_DEF=$(echo "$TASK_DEF_JSON" | jq \
        --arg newval "$INIT_LEAGUES_VALUE" \
        'del(.taskDefinitionArn, .revision, .status, .requiresAttributes,
              .compatibilities, .registeredAt, .registeredBy, .deregisteredAt) |
         .containerDefinitions[0].environment = [
           .containerDefinitions[0].environment[] |
           if .name == "INIT_LEAGUES" then .value = $newval else . end
         ]')

    if [[ "$DRY_RUN" == true ]]; then
        print_warning "[DRY RUN] Would register this task definition:"
        echo "$PATCHED_TASK_DEF" | jq '.containerDefinitions[0].environment[] | select(.name == "INIT_LEAGUES")'
        NEW_TASK_DEF_ARN="(dry-run — no ARN registered)"
        return
    fi

    # Register new task definition revision
    NEW_TASK_DEF_ARN=$(aws ecs register-task-definition \
        --cli-input-json "$PATCHED_TASK_DEF" \
        --region "$AWS_REGION" \
        --query 'taskDefinition.taskDefinitionArn' \
        --output text)

    print_success "New task definition: ${NEW_TASK_DEF_ARN}"
}
```

- [ ] **Step 5: Add rolling deploy and waiter**

Append to `infrastructure/switch-tournament.sh`:

```bash
# ── Rolling deploy ────────────────────────────────────────────────────────────
deploy_and_wait() {
    print_header "Deploying (Rolling Update)"

    if [[ "$DRY_RUN" == true ]]; then
        print_warning "[DRY RUN] Would update ECS service '${SERVICE_NAME}' on cluster '${CLUSTER_NAME}'"
        print_warning "[DRY RUN] Would wait for service to stabilise"
        return
    fi

    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --task-definition "$NEW_TASK_DEF_ARN" \
        --force-new-deployment \
        --region "$AWS_REGION" \
        --output json | jq -r '"Service updated. Desired count: \(.service.desiredCount)"'

    print_info "Waiting for rolling deploy to stabilise (this may take 2-5 minutes)..."
    aws ecs wait services-stable \
        --cluster "$CLUSTER_NAME" \
        --services "$SERVICE_NAME" \
        --region "$AWS_REGION"

    print_success "Service stable. All tasks running new revision."
}
```

- [ ] **Step 6: Add summary and main entrypoint**

Append to `infrastructure/switch-tournament.sh`:

```bash
# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
    print_header "Switch Complete"

    HTTP_ENDPOINT=$(get_stack_output "HTTPEndpoint")
    GRPC_ENDPOINT=$(get_stack_output "GRPCEndpoint")

    print_success "Tournament:    ${TOURNAMENT_NAME}"
    print_success "League ID:     ${LEAGUE_ID}"
    print_success "Season:        ${SEASON}"
    echo ""
    print_info "HTTP endpoint: ${HTTP_ENDPOINT}"
    print_info "gRPC endpoint: ${GRPC_ENDPOINT}"
    echo ""
    print_info "Verify with:"
    print_info "  ./infrastructure/verify-tournament.sh --environment ${ENVIRONMENT}"
    echo ""
    print_info "To revert to AFCON:"
    print_info "  $0 --league-id 6 --season 2025 --name 'AFCON 2025' --environment ${ENVIRONMENT}"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    print_header "Tournament Switch — ${TOURNAMENT_NAME}"
    print_info "Stack:       ${STACK_NAME}"
    print_info "Region:      ${AWS_REGION}"
    print_info "INIT_LEAGUES: ${INIT_LEAGUES_VALUE}"
    [[ "$DRY_RUN" == true ]] && print_warning "DRY RUN MODE — no AWS changes will be made"

    check_prerequisites
    resolve_resources
    patch_and_register_task_def
    deploy_and_wait
    print_summary
}

main
```

- [ ] **Step 7: Make executable and dry-run smoke test**

```bash
chmod +x infrastructure/switch-tournament.sh

# Smoke test: dry run (no AWS calls beyond reading stack — safe)
./infrastructure/switch-tournament.sh \
  --league-id 1 \
  --season 2026 \
  --name "FIFA World Cup 2026" \
  --dry-run
```

Expected output: shows "DRY RUN" banners, prints the patched INIT_LEAGUES JSON block, no actual AWS mutation calls. Exits 0.

- [ ] **Step 8: Smoke test error cases**

```bash
# Missing required args → prints usage and exits 1
./infrastructure/switch-tournament.sh --league-id 1
# Expected: "✗  --league-id, --season, and --name are required" + usage text, exit 1

# Invalid environment → exits 1
./infrastructure/switch-tournament.sh \
  --league-id 1 --season 2026 --name "Test" --environment invalid
# Expected: "✗  Invalid environment 'invalid'. Must be production or staging.", exit 1
```

---

## Task 2: `verify-tournament.sh`

**Files:**
- Create: `infrastructure/verify-tournament.sh`

**Interfaces:**
- Consumes: CloudFormation output `HTTPEndpoint`; REST endpoints `GET /health` and `GET /api/league/:id/season/:season`
- Produces: exit 0 (server healthy and serving correct tournament) or exit 1 (unhealthy / wrong tournament)

- [ ] **Step 1: Create the file**

Create `infrastructure/verify-tournament.sh`:

```bash
#!/bin/bash
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

print_header()  { echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n  $1\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }
print_info()    { echo -e "${BLUE}ℹ${NC}  $1"; }
print_success() { echo -e "${GREEN}✓${NC}  $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC}  $1"; }
print_error()   { echo -e "${RED}✗${NC}  $1"; }

# ── Defaults ──────────────────────────────────────────────────────────────────
AWS_REGION="${AWS_REGION:-eu-north-1}"
ENVIRONMENT="production"
# Optional: expected league ID/season to assert against. If empty, just prints what's live.
EXPECT_LEAGUE_ID=""
EXPECT_SEASON=""

# ── Arg parsing ───────────────────────────────────────────────────────────────
usage() {
    echo "Usage: $0 [--environment <env>] [--expect-league-id <id>] [--expect-season <year>]"
    echo ""
    echo "  --environment        production|staging  (default: production)"
    echo "  --expect-league-id   Assert the server is serving this league ID (optional)"
    echo "  --expect-season      Assert the server is serving this season (optional)"
    echo ""
    echo "Examples:"
    echo "  $0 --environment production"
    echo "  $0 --expect-league-id 1 --expect-season 2026"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --environment)       ENVIRONMENT="$2";       shift 2 ;;
        --expect-league-id)  EXPECT_LEAGUE_ID="$2";  shift 2 ;;
        --expect-season)     EXPECT_SEASON="$2";     shift 2 ;;
        --help|-h) usage ;;
        *) print_error "Unknown argument: $1"; usage ;;
    esac
done

STACK_NAME="afcon-${ENVIRONMENT}"
```

- [ ] **Step 2: Add prerequisite check and endpoint resolver**

Append to `infrastructure/verify-tournament.sh`:

```bash
# ── Prerequisites ─────────────────────────────────────────────────────────────
check_prerequisites() {
    command -v aws  &>/dev/null || { print_error "AWS CLI not installed"; exit 1; }
    command -v curl &>/dev/null || { print_error "curl not installed"; exit 1; }
    command -v jq   &>/dev/null || { print_error "jq not installed. Run: brew install jq"; exit 1; }
    aws sts get-caller-identity --region "$AWS_REGION" &>/dev/null || {
        print_error "AWS credentials not configured"
        exit 1
    }
}

get_http_endpoint() {
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$AWS_REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='HTTPEndpoint'].OutputValue" \
        --output text 2>/dev/null
}

get_grpc_endpoint() {
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$AWS_REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='GRPCEndpoint'].OutputValue" \
        --output text 2>/dev/null
}
```

- [ ] **Step 3: Add health and tournament checks**

Append to `infrastructure/verify-tournament.sh`:

```bash
# ── Checks ────────────────────────────────────────────────────────────────────
check_health() {
    local ENDPOINT="$1"
    print_info "GET ${ENDPOINT}/health"

    HEALTH_RESPONSE=$(curl -sf --max-time 10 "${ENDPOINT}/health" 2>/dev/null) || {
        print_error "Health check failed — server unreachable at ${ENDPOINT}"
        exit 1
    }

    STATUS=$(echo "$HEALTH_RESPONSE" | jq -r '.status // empty')
    [[ "$STATUS" == "healthy" ]] || {
        print_error "Server returned unhealthy status: ${HEALTH_RESPONSE}"
        exit 1
    }

    print_success "Health: ${STATUS}"
}

check_league() {
    local ENDPOINT="$1"
    local LEAGUE_ID="$2"
    local SEASON="$3"

    print_info "GET ${ENDPOINT}/api/league/${LEAGUE_ID}/season/${SEASON}"

    LEAGUE_RESPONSE=$(curl -sf --max-time 15 \
        "${ENDPOINT}/api/league/${LEAGUE_ID}/season/${SEASON}" 2>/dev/null) || {
        print_error "League endpoint failed for leagueId=${LEAGUE_ID} season=${SEASON}"
        exit 1
    }

    LEAGUE_NAME=$(echo "$LEAGUE_RESPONSE" | jq -r '.league.name // .name // empty')
    LEAGUE_COUNTRY=$(echo "$LEAGUE_RESPONSE" | jq -r '.league.country // .country // empty')

    if [[ -n "$LEAGUE_NAME" ]]; then
        print_success "League: ${LEAGUE_NAME} (${LEAGUE_COUNTRY})"
    else
        print_warning "League endpoint responded but returned unexpected JSON:"
        echo "$LEAGUE_RESPONSE" | jq '.' 2>/dev/null || echo "$LEAGUE_RESPONSE"
    fi
}

detect_active_tournament() {
    # Try both known tournaments and print which ones the server responds to
    local ENDPOINT="$1"
    print_info "Probing active tournaments..."

    for COMBO in "1:2026:FIFA World Cup 2026" "6:2025:AFCON 2025"; do
        LID="${COMBO%%:*}"; REST="${COMBO#*:}"; SEASON="${REST%%:*}"; NAME="${REST#*:}"
        RESP=$(curl -sf --max-time 10 "${ENDPOINT}/api/league/${LID}/season/${SEASON}" 2>/dev/null) || continue
        RNAME=$(echo "$RESP" | jq -r '.league.name // .name // empty')
        [[ -n "$RNAME" ]] && print_success "Active: ${NAME} (server returned: ${RNAME})"
    done
}
```

- [ ] **Step 4: Add main entrypoint**

Append to `infrastructure/verify-tournament.sh`:

```bash
# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    print_header "Tournament Verification — ${ENVIRONMENT}"

    check_prerequisites

    HTTP_ENDPOINT=$(get_http_endpoint)
    GRPC_ENDPOINT=$(get_grpc_endpoint)

    [[ -z "$HTTP_ENDPOINT" ]] && {
        print_error "Stack '${STACK_NAME}' not found or missing HTTPEndpoint output"
        exit 1
    }

    print_info "HTTP endpoint: ${HTTP_ENDPOINT}"
    print_info "gRPC endpoint: ${GRPC_ENDPOINT}"
    echo ""

    check_health "$HTTP_ENDPOINT"

    if [[ -n "$EXPECT_LEAGUE_ID" && -n "$EXPECT_SEASON" ]]; then
        check_league "$HTTP_ENDPOINT" "$EXPECT_LEAGUE_ID" "$EXPECT_SEASON"
    else
        detect_active_tournament "$HTTP_ENDPOINT"
    fi

    echo ""
    print_success "Verification complete."
}

main
```

- [ ] **Step 5: Make executable and test**

```bash
chmod +x infrastructure/verify-tournament.sh

# Test: verify current live server (no assertions — just print what's active)
./infrastructure/verify-tournament.sh --environment production
# Expected: health ✓, prints which tournaments are responding

# Test: assert WC is active (run this AFTER switch-tournament.sh completes)
./infrastructure/verify-tournament.sh \
  --environment production \
  --expect-league-id 1 \
  --expect-season 2026
# Expected: health ✓, "League: FIFA World Cup ..." ✓, exits 0

# Test: assert wrong tournament → exits 1
./infrastructure/verify-tournament.sh \
  --environment production \
  --expect-league-id 999 \
  --expect-season 9999
# Expected: "League endpoint failed" or empty name, exits 1
```

---

## Full World Cup Switch — End-to-End Runbook

Once both scripts exist, the complete WC launch sequence is:

```bash
# 1. Dry-run to confirm what will change
./infrastructure/switch-tournament.sh \
  --league-id 1 --season 2026 --name "FIFA World Cup 2026" \
  --dry-run

# 2. Execute the switch (takes ~5 minutes)
./infrastructure/switch-tournament.sh \
  --league-id 1 --season 2026 --name "FIFA World Cup 2026"

# 3. Verify
./infrastructure/verify-tournament.sh \
  --expect-league-id 1 --expect-season 2026

# 4. Archive FWC2026 iOS target and submit to App Store
```

To revert to AFCON at any time:
```bash
./infrastructure/switch-tournament.sh \
  --league-id 6 --season 2025 --name "AFCON 2025"
```
