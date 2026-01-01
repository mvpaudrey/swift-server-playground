#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"

# Helper functions
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Prompt for secret value (hidden input)
prompt_secret() {
    local PROMPT="$1"
    local VALUE=""

    read -s -p "${PROMPT}: " VALUE
    echo ""
    echo "$VALUE"
}

# Prompt for regular value
prompt_value() {
    local PROMPT="$1"
    local DEFAULT="$2"
    local VALUE=""

    if [[ -n "$DEFAULT" ]]; then
        read -p "${PROMPT} [${DEFAULT}]: " VALUE
        VALUE="${VALUE:-$DEFAULT}"
    else
        read -p "${PROMPT}: " VALUE
    fi

    echo "$VALUE"
}

# Update API Football secret
update_api_football_secret() {
    local ENV=$1

    print_header "API-Football Configuration"

    echo "Get your API key from: https://www.api-football.com/"
    echo ""

    API_KEY=$(prompt_secret "Enter API-Football API Key")

    if [[ -z "$API_KEY" ]]; then
        print_error "API key cannot be empty"
        return 1
    fi

    SECRET_NAME="${ENV}-afcon-api-football-key"
    SECRET_VALUE="{\"api_key\":\"${API_KEY}\"}"

    print_info "Updating secret: ${SECRET_NAME}"
    aws secretsmanager update-secret \
        --secret-id "${SECRET_NAME}" \
        --secret-string "${SECRET_VALUE}" \
        --region "${AWS_REGION}" \
        > /dev/null

    print_success "API-Football secret updated"
}

# Update APNS secret
update_apns_secret() {
    local ENV=$1

    print_header "Apple Push Notification Service (APNS) Configuration"

    echo "Get your APNS credentials from: https://developer.apple.com/account"
    echo ""

    KEY_ID=$(prompt_value "Enter APNS Key ID" "")
    TEAM_ID=$(prompt_value "Enter APNS Team ID" "")
    TOPIC=$(prompt_value "Enter APNS Topic (Bundle ID)" "com.yourapp.bundleid")

    if [[ -z "$KEY_ID" ]] || [[ -z "$TEAM_ID" ]]; then
        print_error "Key ID and Team ID cannot be empty"
        return 1
    fi

    SECRET_NAME="${ENV}-afcon-apns"
    SECRET_VALUE="{\"key_id\":\"${KEY_ID}\",\"team_id\":\"${TEAM_ID}\",\"topic\":\"${TOPIC}\"}"

    print_info "Updating secret: ${SECRET_NAME}"
    aws secretsmanager update-secret \
        --secret-id "${SECRET_NAME}" \
        --secret-string "${SECRET_VALUE}" \
        --region "${AWS_REGION}" \
        > /dev/null

    print_success "APNS secret updated"
}

# Update FCM secret
update_fcm_secret() {
    local ENV=$1

    print_header "Firebase Cloud Messaging (FCM) Configuration"

    echo "Get your FCM server key from: https://console.firebase.google.com/"
    echo "Navigate to: Project Settings → Cloud Messaging → Server Key"
    echo ""

    FCM_KEY=$(prompt_secret "Enter FCM Server Key")

    if [[ -z "$FCM_KEY" ]]; then
        print_error "FCM server key cannot be empty"
        return 1
    fi

    SECRET_NAME="${ENV}-afcon-fcm"
    SECRET_VALUE="{\"server_key\":\"${FCM_KEY}\"}"

    print_info "Updating secret: ${SECRET_NAME}"
    aws secretsmanager update-secret \
        --secret-id "${SECRET_NAME}" \
        --secret-string "${SECRET_VALUE}" \
        --region "${AWS_REGION}" \
        > /dev/null

    print_success "FCM secret updated"
}

# Interactive mode - update all secrets
update_all_secrets() {
    local ENV=$1

    echo "This script will help you update all AWS Secrets Manager secrets."
    echo ""
    print_warning "Make sure you have your API keys ready before proceeding."
    echo ""
    read -p "Press Enter to continue or Ctrl+C to cancel..."

    update_api_football_secret "$ENV"
    update_apns_secret "$ENV"
    update_fcm_secret "$ENV"

    print_header "All Secrets Updated!"
    print_success "Your secrets have been updated successfully"
}

# Update specific secret
update_specific_secret() {
    local ENV=$1
    local SECRET_TYPE=$2

    case "$SECRET_TYPE" in
        api-football|api)
            update_api_football_secret "$ENV"
            ;;
        apns|apple)
            update_apns_secret "$ENV"
            ;;
        fcm|firebase)
            update_fcm_secret "$ENV"
            ;;
        *)
            print_error "Unknown secret type: $SECRET_TYPE"
            echo "Valid types: api-football, apns, fcm"
            exit 1
            ;;
    esac
}

# Main function
main() {
    local ENVIRONMENT="${1:-production}"
    local SECRET_TYPE="${2:-}"

    if [[ ! "$ENVIRONMENT" =~ ^(development|staging|production)$ ]]; then
        print_error "Invalid environment. Must be one of: development, staging, production"
        echo "Usage: $0 <environment> [secret-type]"
        echo ""
        echo "Examples:"
        echo "  $0 production              # Update all secrets"
        echo "  $0 staging api-football    # Update only API-Football secret"
        echo "  $0 production apns         # Update only APNS secret"
        exit 1
    fi

    print_header "AWS Secrets Manager Update"
    print_info "Environment: ${ENVIRONMENT}"
    print_info "Region: ${AWS_REGION}"

    # Check prerequisites
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        exit 1
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured"
        exit 1
    fi

    if [[ -z "$SECRET_TYPE" ]]; then
        update_all_secrets "$ENVIRONMENT"
    else
        update_specific_secret "$ENVIRONMENT" "$SECRET_TYPE"
    fi
}

# Run main function
main "$@"
