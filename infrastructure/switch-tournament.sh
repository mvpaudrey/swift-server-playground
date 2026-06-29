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
AWS_REGION="${AWS_REGION:-eu-west-3}"
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

[[ "$TOURNAMENT_NAME" =~ : ]] && {
    print_error "Tournament name must not contain colons: '${TOURNAMENT_NAME}'"
    exit 1
}

[[ "$ENVIRONMENT" =~ ^(production|staging)$ ]] || {
    print_error "Invalid environment '$ENVIRONMENT'. Must be production or staging."
    exit 1
}

STACK_NAME="tournament-${ENVIRONMENT}"
INIT_LEAGUES_VALUE="${LEAGUE_ID}:${SEASON}:${TOURNAMENT_NAME}"

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
    [[ -z "$CURRENT_LEAGUES" ]] && {
        print_error "INIT_LEAGUES not found in current task definition."
        print_error "Add INIT_LEAGUES to the ECS task definition before using this script."
        exit 1
    }
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

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
    if [[ "$DRY_RUN" == true ]]; then
        print_header "Dry Run Summary (no changes made)"
    else
        print_header "Switch Complete"
    fi

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
