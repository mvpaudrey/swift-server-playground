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

# Delete Redis replication groups
cleanup_redis() {
    local ENV=$1

    print_header "Cleaning Up Redis Replication Groups"

    # Find Redis replication groups
    REDIS_GROUPS=$(aws elasticache describe-replication-groups \
        --region "${AWS_REGION}" \
        --query "ReplicationGroups[?starts_with(ReplicationGroupId, '${ENV}-afcon')].ReplicationGroupId" \
        --output text)

    if [[ -z "$REDIS_GROUPS" ]]; then
        print_info "No Redis replication groups found for ${ENV}"
        return 0
    fi

    for GROUP_ID in $REDIS_GROUPS; do
        print_info "Found Redis replication group: ${GROUP_ID}"

        # Check status
        STATUS=$(aws elasticache describe-replication-groups \
            --replication-group-id "${GROUP_ID}" \
            --region "${AWS_REGION}" \
            --query 'ReplicationGroups[0].Status' \
            --output text)

        print_info "Status: ${STATUS}"

        if [[ "$STATUS" == "creating" ]]; then
            print_warning "Redis group is still creating. Waiting 30 seconds..."
            sleep 30

            # Check again
            STATUS=$(aws elasticache describe-replication-groups \
                --replication-group-id "${GROUP_ID}" \
                --region "${AWS_REGION}" \
                --query 'ReplicationGroups[0].Status' \
                --output text 2>/dev/null || echo "not-found")
        fi

        if [[ "$STATUS" != "not-found" ]]; then
            print_info "Deleting Redis replication group: ${GROUP_ID}"
            aws elasticache delete-replication-group \
                --replication-group-id "${GROUP_ID}" \
                --region "${AWS_REGION}" 2>/dev/null || print_warning "Failed to delete (may already be deleting)"

            print_success "Deletion initiated for ${GROUP_ID}"
        fi
    done

    print_info "Waiting for Redis cleanup to complete (this may take a few minutes)..."
    sleep 60
}

# Delete RDS instances
cleanup_rds() {
    local ENV=$1

    print_header "Cleaning Up RDS Instances"

    # Find RDS instances
    DB_INSTANCES=$(aws rds describe-db-instances \
        --region "${AWS_REGION}" \
        --query "DBInstances[?contains(DBInstanceIdentifier, '${ENV}-afcon') || contains(DBInstanceIdentifier, 'afcon')].DBInstanceIdentifier" \
        --output text)

    if [[ -z "$DB_INSTANCES" ]]; then
        print_info "No RDS instances found for ${ENV}"
        return 0
    fi

    for DB_ID in $DB_INSTANCES; do
        print_info "Found RDS instance: ${DB_ID}"

        print_info "Deleting RDS instance: ${DB_ID} (skip final snapshot)"
        aws rds delete-db-instance \
            --db-instance-identifier "${DB_ID}" \
            --skip-final-snapshot \
            --region "${AWS_REGION}" 2>/dev/null || print_warning "Failed to delete (may already be deleting)"

        print_success "Deletion initiated for ${DB_ID}"
    done
}

# Delete CloudFormation stack
cleanup_stack() {
    local ENV=$1
    local STACK_NAME="afcon-${ENV}"

    print_header "Cleaning Up CloudFormation Stack"

    # Check if stack exists
    if ! aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --region "${AWS_REGION}" &> /dev/null; then
        print_info "Stack ${STACK_NAME} does not exist"
        return 0
    fi

    # Get stack status
    STATUS=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --region "${AWS_REGION}" \
        --query 'Stacks[0].StackStatus' \
        --output text)

    print_info "Stack status: ${STATUS}"

    if [[ "$STATUS" == "ROLLBACK_FAILED" || "$STATUS" == "DELETE_FAILED" ]]; then
        print_warning "Stack is in ${STATUS} state. Attempting to continue deletion..."

        # Try to continue rollback
        print_info "Continuing stack rollback..."
        aws cloudformation continue-update-rollback \
            --stack-name "${STACK_NAME}" \
            --region "${AWS_REGION}" 2>/dev/null || print_warning "Could not continue rollback"

        sleep 30
    fi

    # Delete the stack
    print_info "Deleting CloudFormation stack: ${STACK_NAME}"
    aws cloudformation delete-stack \
        --stack-name "${STACK_NAME}" \
        --region "${AWS_REGION}"

    print_info "Waiting for stack deletion to complete..."
    aws cloudformation wait stack-delete-complete \
        --stack-name "${STACK_NAME}" \
        --region "${AWS_REGION}" 2>&1 || {
            print_warning "Stack deletion encountered issues. Check AWS console for details."
            return 1
        }

    print_success "Stack ${STACK_NAME} deleted successfully"
}

# Main function
main() {
    local ENVIRONMENT="${1:-staging}"

    if [[ ! "$ENVIRONMENT" =~ ^(development|staging|production)$ ]]; then
        print_error "Invalid environment. Must be one of: development, staging, production"
        echo "Usage: $0 [environment]"
        exit 1
    fi

    print_header "AFCON Infrastructure Cleanup"
    print_info "Environment: ${ENVIRONMENT}"
    print_warning "This will delete all resources for the ${ENVIRONMENT} environment"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo

    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_info "Cleanup cancelled"
        exit 0
    fi

    cleanup_redis "$ENVIRONMENT"
    cleanup_rds "$ENVIRONMENT"
    cleanup_stack "$ENVIRONMENT"

    print_header "Cleanup Complete!"
    print_success "All resources for ${ENVIRONMENT} have been cleaned up"
    print_info "You can now redeploy using: ./infrastructure/deploy.sh ${ENVIRONMENT}"
}

# Run main function
main "$@"
