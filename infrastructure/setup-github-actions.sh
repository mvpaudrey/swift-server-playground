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
IAM_USER_NAME="github-actions-deploy"
POLICY_NAME="GitHubActionsDeployPolicy"

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

# Create IAM user
create_iam_user() {
    print_header "Creating IAM User for GitHub Actions"

    # Check if user already exists
    if aws iam get-user --user-name "${IAM_USER_NAME}" &> /dev/null; then
        print_warning "IAM user ${IAM_USER_NAME} already exists"
    else
        print_info "Creating IAM user: ${IAM_USER_NAME}"
        aws iam create-user --user-name "${IAM_USER_NAME}"
        print_success "IAM user created"
    fi
}

# Create and attach custom policy
create_custom_policy() {
    print_header "Creating Custom IAM Policy"

    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

    # Create policy document
    POLICY_DOC=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecs:DescribeTaskDefinition",
        "ecs:RegisterTaskDefinition",
        "ecs:UpdateService",
        "ecs:DescribeServices"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:DescribeListeners"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:PassRole"
      ],
      "Resource": [
        "arn:aws:iam::${ACCOUNT_ID}:role/*-ECSTaskExecutionRole-*",
        "arn:aws:iam::${ACCOUNT_ID}:role/*-ECSTaskRole-*"
      ]
    }
  ]
}
EOF
)

    # Check if policy exists
    POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
    if aws iam get-policy --policy-arn "${POLICY_ARN}" &> /dev/null; then
        print_warning "Policy ${POLICY_NAME} already exists"

        # Get current policy version
        CURRENT_VERSION=$(aws iam get-policy --policy-arn "${POLICY_ARN}" --query 'Policy.DefaultVersionId' --output text)

        # Create new version
        print_info "Creating new policy version..."
        aws iam create-policy-version \
            --policy-arn "${POLICY_ARN}" \
            --policy-document "${POLICY_DOC}" \
            --set-as-default

        # Delete old version
        aws iam delete-policy-version \
            --policy-arn "${POLICY_ARN}" \
            --version-id "${CURRENT_VERSION}"

        print_success "Policy updated"
    else
        print_info "Creating IAM policy: ${POLICY_NAME}"
        aws iam create-policy \
            --policy-name "${POLICY_NAME}" \
            --policy-document "${POLICY_DOC}"
        print_success "Policy created"
    fi

    # Attach policy to user
    print_info "Attaching policy to user..."
    aws iam attach-user-policy \
        --user-name "${IAM_USER_NAME}" \
        --policy-arn "${POLICY_ARN}" 2>/dev/null || print_warning "Policy already attached"
    print_success "Policy attached"
}

# Create access keys
create_access_keys() {
    print_header "Creating Access Keys"

    # Check existing access keys
    EXISTING_KEYS=$(aws iam list-access-keys --user-name "${IAM_USER_NAME}" --query 'AccessKeyMetadata[].AccessKeyId' --output text)

    if [[ -n "$EXISTING_KEYS" ]]; then
        print_warning "Access keys already exist for user ${IAM_USER_NAME}"
        echo "Existing keys:"
        echo "$EXISTING_KEYS"
        echo ""
        read -p "Do you want to create new access keys? This will require you to delete old keys. (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Skipping access key creation"
            return 0
        fi

        # Delete old keys
        for KEY_ID in $EXISTING_KEYS; do
            print_info "Deleting old key: ${KEY_ID}"
            aws iam delete-access-key --user-name "${IAM_USER_NAME}" --access-key-id "${KEY_ID}"
        done
    fi

    print_info "Creating new access keys..."
    CREDENTIALS=$(aws iam create-access-key --user-name "${IAM_USER_NAME}" --output json)

    ACCESS_KEY_ID=$(echo "$CREDENTIALS" | jq -r '.AccessKey.AccessKeyId')
    SECRET_ACCESS_KEY=$(echo "$CREDENTIALS" | jq -r '.AccessKey.SecretAccessKey')

    print_success "Access keys created successfully"
    echo ""
}

# Print GitHub setup instructions
print_github_instructions() {
    print_header "GitHub Secrets Setup"

    echo "Add the following secrets to your GitHub repository:"
    echo ""
    echo "1. Go to your repository on GitHub"
    echo "2. Navigate to: ${YELLOW}Settings → Secrets and variables → Actions${NC}"
    echo "3. Click ${YELLOW}New repository secret${NC}"
    echo "4. Add these two secrets:"
    echo ""
    echo "   ${GREEN}Name:${NC} AWS_ACCESS_KEY_ID"
    echo "   ${GREEN}Value:${NC} ${ACCESS_KEY_ID}"
    echo ""
    echo "   ${GREEN}Name:${NC} AWS_SECRET_ACCESS_KEY"
    echo "   ${GREEN}Value:${NC} ${SECRET_ACCESS_KEY}"
    echo ""
    print_warning "IMPORTANT: Save these credentials securely. They won't be shown again."
    echo ""

    # Optionally save to file
    read -p "Do you want to save credentials to a file (credentials.txt)? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cat > credentials.txt <<EOF
AWS_ACCESS_KEY_ID=${ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${SECRET_ACCESS_KEY}
EOF
        chmod 600 credentials.txt
        print_success "Credentials saved to credentials.txt"
        print_warning "Remember to delete this file after adding secrets to GitHub!"
    fi
}

# Main function
main() {
    print_header "GitHub Actions IAM Setup"

    # Check prerequisites
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed"
        exit 1
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured"
        exit 1
    fi

    create_iam_user
    create_custom_policy
    create_access_keys
    print_github_instructions

    print_header "Setup Complete!"
    print_success "GitHub Actions IAM user is ready"
}

# Run main function
main "$@"
