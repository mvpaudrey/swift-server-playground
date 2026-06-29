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

STACK_NAME="tournament-${ENVIRONMENT}"

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
    local LID REST SEASON NAME RESP RNAME COMBO
    print_info "Probing active tournaments..."

    for COMBO in "1:2026:FIFA World Cup 2026" "6:2025:AFCON 2025"; do
        LID="${COMBO%%:*}"; REST="${COMBO#*:}"; SEASON="${REST%%:*}"; NAME="${REST#*:}"
        RESP=$(curl -sf --max-time 10 "${ENDPOINT}/api/league/${LID}/season/${SEASON}" 2>/dev/null) || continue
        RNAME=$(echo "$RESP" | jq -r '.league.name // .name // empty')
        [[ -n "$RNAME" ]] && print_success "Active: ${NAME} (server returned: ${RNAME})"
    done
}

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

    if [[ -n "$EXPECT_LEAGUE_ID" && -z "$EXPECT_SEASON" ]] || \
       [[ -z "$EXPECT_LEAGUE_ID" && -n "$EXPECT_SEASON" ]]; then
        print_warning "--expect-league-id and --expect-season must both be set to assert a specific tournament."
        print_warning "Running detection mode instead."
    fi

    if [[ -n "$EXPECT_LEAGUE_ID" && -n "$EXPECT_SEASON" ]]; then
        check_league "$HTTP_ENDPOINT" "$EXPECT_LEAGUE_ID" "$EXPECT_SEASON"
    else
        detect_active_tournament "$HTTP_ENDPOINT"
    fi

    echo ""
    print_success "Verification complete."
}

main
