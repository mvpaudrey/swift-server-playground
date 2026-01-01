#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION="${AWS_REGION:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Check AWS CLI is installed
check_prerequisites() {
    print_header "Checking Prerequisites"

    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    print_success "AWS CLI is installed"

    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed. Please install it first."
        exit 1
    fi
    print_success "jq is installed"

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials are not configured. Run 'aws configure' first."
        exit 1
    fi
    print_success "AWS credentials are configured"

    if [[ -z "${AWS_REGION}" ]]; then
        AWS_REGION="$(aws configure get region 2>/dev/null)"
        if [[ -z "${AWS_REGION}" ]]; then
            AWS_REGION="us-east-1"
        fi
    fi

    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    print_info "AWS Account ID: ${ACCOUNT_ID}"
    print_info "AWS Region: ${AWS_REGION}"
}

# Deploy CloudFormation stack
deploy_stack() {
    local ENV=$1
    local STACK_NAME="afcon-${ENV}"

    print_header "Deploying CloudFormation Stack: ${STACK_NAME}"

    # Check if stack exists
    if aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${AWS_REGION}" &> /dev/null; then
        print_warning "Stack ${STACK_NAME} already exists. Updating..."

        aws cloudformation update-stack \
            --stack-name "${STACK_NAME}" \
            --template-body "file://${SCRIPT_DIR}/cloudformation.yaml" \
            --parameters ParameterKey=EnvironmentName,ParameterValue="${ENV}" \
            --capabilities CAPABILITY_IAM \
            --region "${AWS_REGION}" || {
                if [[ $? -eq 254 ]]; then
                    print_info "No updates to be performed"
                    return 0
                else
                    print_error "Failed to update stack"
                    return 1
                fi
            }

        print_info "Waiting for stack update to complete..."
        aws cloudformation wait stack-update-complete \
            --stack-name "${STACK_NAME}" \
            --region "${AWS_REGION}"
    else
        print_info "Creating new stack ${STACK_NAME}..."

        aws cloudformation create-stack \
            --stack-name "${STACK_NAME}" \
            --template-body "file://${SCRIPT_DIR}/cloudformation.yaml" \
            --parameters ParameterKey=EnvironmentName,ParameterValue="${ENV}" \
            --capabilities CAPABILITY_IAM \
            --region "${AWS_REGION}"

        print_info "Waiting for stack creation to complete (this may take 15-20 minutes)..."
        aws cloudformation wait stack-create-complete \
            --stack-name "${STACK_NAME}" \
            --region "${AWS_REGION}"
    fi

    print_success "Stack ${STACK_NAME} deployed successfully"

    # Get stack outputs
    print_header "Stack Outputs"
    aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --query 'Stacks[0].Outputs' \
        --region "${AWS_REGION}" \
        --output table
}

# Print next steps
print_next_steps() {
    local ENV=$1

    print_header "Next Steps"

    echo "1. Update AWS Secrets Manager with your API keys:"
    echo ""
    echo "   ${YELLOW}# API-Football Key${NC}"
    echo "   aws secretsmanager update-secret \\"
    echo "     --secret-id ${ENV}-afcon-api-football-key \\"
    echo "     --secret-string '{\"api_key\":\"YOUR_ACTUAL_API_KEY\"}' \\"
    echo "     --region ${AWS_REGION}"
    echo ""
    echo "   ${YELLOW}# APNS Credentials${NC}"
    echo "   aws secretsmanager update-secret \\"
    echo "     --secret-id ${ENV}-afcon-apns \\"
    echo "     --secret-string '{\"key_id\":\"YOUR_KEY_ID\",\"team_id\":\"YOUR_TEAM_ID\",\"topic\":\"com.yourapp.bundleid\"}' \\"
    echo "     --region ${AWS_REGION}"
    echo ""
    echo "   ${YELLOW}# FCM Server Key${NC}"
    echo "   aws secretsmanager update-secret \\"
    echo "     --secret-id ${ENV}-afcon-fcm \\"
    echo "     --secret-string '{\"server_key\":\"YOUR_FCM_SERVER_KEY\"}' \\"
    echo "     --region ${AWS_REGION}"
    echo ""
    echo "   ${BLUE}Or run:${NC} ./infrastructure/update-secrets.sh ${ENV}"
    echo ""
    echo "2. Set up GitHub Actions credentials:"
    echo "   ${BLUE}Run:${NC} ./infrastructure/setup-github-actions.sh"
    echo ""
    echo "3. Push to your repository to trigger deployment:"
    echo "   git push origin main"
    echo ""
}

# Main function
main() {
    local ENVIRONMENT="${1:-production}"

    if [[ ! "$ENVIRONMENT" =~ ^(development|staging|production)$ ]]; then
        print_error "Invalid environment. Must be one of: development, staging, production"
        echo "Usage: $0 [environment]"
        exit 1
    fi

    print_header "AFCON Server AWS Deployment"
    print_info "Environment: ${ENVIRONMENT}"

    check_prerequisites
    deploy_stack "${ENVIRONMENT}"
    print_next_steps "${ENVIRONMENT}"

    print_header "Deployment Complete!"
    print_success "Infrastructure for ${ENVIRONMENT} is ready"
}

# Run main function
main "$@"
