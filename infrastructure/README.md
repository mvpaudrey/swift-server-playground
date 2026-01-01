# AWS Infrastructure Deployment Guide

This directory contains AWS CloudFormation templates and deployment scripts for the AFCON Swift gRPC server.

## Prerequisites

Before deploying, ensure you have:

- [AWS CLI](https://aws.amazon.com/cli/) installed and configured
- [jq](https://stedolan.github.io/jq/) installed for JSON processing
- AWS account with appropriate permissions
- API keys ready:
  - API-Football API key (from https://www.api-football.com/)
  - Apple APNS credentials (from https://developer.apple.com/account)
  - Firebase FCM server key (from https://console.firebase.google.com/)

### Install Prerequisites

```bash
# macOS
brew install awscli jq

# Linux
sudo apt-get install awscli jq

# Configure AWS CLI
aws configure
```

## Quick Start

Deploy the complete infrastructure in 3 simple steps:

### 1. Deploy AWS Infrastructure

```bash
# Deploy to production
./infrastructure/deploy.sh production

# Or deploy to staging
./infrastructure/deploy.sh staging
```

This creates:
- VPC with public/private subnets across 2 availability zones
- RDS PostgreSQL database (with automatic backups)
- ElastiCache Redis cluster
- ECS Fargate cluster
- Application Load Balancer (HTTP/HTTPS)
- ECR repository for Docker images
- IAM roles and security groups
- CloudWatch logs and alarms

**Time:** 15-20 minutes for first deployment

### 2. Set Up GitHub Actions

```bash
./infrastructure/setup-github-actions.sh
```

This will:
- Create IAM user `github-actions-deploy`
- Attach required policies for ECR and ECS
- Generate access keys
- Display instructions for adding secrets to GitHub

**Important:** Add the displayed credentials to your GitHub repository:
- Go to: `Settings → Secrets and variables → Actions`
- Add `AWS_ACCESS_KEY_ID`
- Add `AWS_SECRET_ACCESS_KEY`

### 3. Update Application Secrets

```bash
# Update all secrets interactively
./infrastructure/update-secrets.sh production

# Or update specific secrets
./infrastructure/update-secrets.sh production api-football
./infrastructure/update-secrets.sh production apns
./infrastructure/update-secrets.sh production fcm
```

## Script Reference

### deploy.sh

Deploys or updates the CloudFormation stack.

```bash
./infrastructure/deploy.sh [environment]

# Examples:
./infrastructure/deploy.sh production   # Deploy to production
./infrastructure/deploy.sh staging      # Deploy to staging
./infrastructure/deploy.sh development  # Deploy to development
```

**What it does:**
- Validates prerequisites (AWS CLI, jq, credentials)
- Creates or updates CloudFormation stack
- Waits for stack creation/update to complete
- Displays stack outputs (endpoints, URLs)
- Shows next steps

### setup-github-actions.sh

Creates IAM user and credentials for GitHub Actions.

```bash
./infrastructure/setup-github-actions.sh
```

**What it does:**
- Creates IAM user `github-actions-deploy`
- Creates custom IAM policy with minimal required permissions
- Generates access keys
- Provides GitHub secrets setup instructions
- Optionally saves credentials to file

**Permissions granted:**
- ECR: Push and pull Docker images
- ECS: Update services and task definitions
- ELB: Describe load balancers
- IAM: Pass role to ECS tasks

### update-secrets.sh

Updates AWS Secrets Manager secrets with your API keys.

```bash
./infrastructure/update-secrets.sh <environment> [secret-type]

# Examples:
./infrastructure/update-secrets.sh production              # Update all secrets
./infrastructure/update-secrets.sh staging api-football    # Update API-Football only
./infrastructure/update-secrets.sh production apns         # Update APNS only
./infrastructure/update-secrets.sh production fcm          # Update FCM only
```

**Secret types:**
- `api-football` (alias: `api`) - API-Football API key
- `apns` (alias: `apple`) - Apple Push Notification Service
- `fcm` (alias: `firebase`) - Firebase Cloud Messaging

## CloudFormation Stack Details

### Resources Created

#### Networking
- **VPC**: 10.0.0.0/16 CIDR block
- **Public Subnets**: 2 subnets across AZs (for ALB)
- **Private Subnets**: 2 subnets across AZs (for ECS tasks, RDS, Redis)
- **NAT Gateway**: For outbound connectivity from private subnets
- **Security Groups**: ALB, ECS, RDS, Redis with minimal required access

#### Database
- **RDS PostgreSQL 15.4**
  - Instance class: db.t4g.micro (configurable)
  - Storage: 20GB GP3 (encrypted)
  - Multi-AZ: Production only
  - Automated backups: 7 days (production), 1 day (staging)
  - Database name: `afcon`

#### Cache
- **ElastiCache Redis**
  - Node type: cache.t4g.micro (configurable)
  - 2-node cluster with automatic failover
  - Encryption at rest enabled

#### Compute
- **ECS Fargate Cluster**
  - Task CPU: 512 units (0.5 vCPU)
  - Task Memory: 1024 MB
  - Desired count: 2 tasks
  - Auto-scaling: Up to 10 tasks based on CPU
  - Mix of FARGATE and FARGATE_SPOT for cost optimization

#### Load Balancing
- **Application Load Balancer**
  - HTTP listener (port 80)
  - HTTPS listener (port 443, if certificate provided)
  - Health checks on `/health` endpoint
  - gRPC support enabled

#### Container Registry
- **ECR Repository**: `afcon-server`
  - Image scanning on push
  - Lifecycle policy: Keep last 10 images

#### Monitoring
- **CloudWatch Logs**: 30 days retention (production), 7 days (staging)
- **CloudWatch Alarms**:
  - High CPU usage (>80%)
  - High database connections (>80%)

#### Secrets
- **AWS Secrets Manager**:
  - Database password (auto-generated)
  - API-Football API key
  - APNS credentials
  - FCM server key

### Stack Parameters

You can customize the deployment by modifying parameters in `cloudformation.yaml`:

```yaml
Parameters:
  EnvironmentName: production|staging|development
  VpcCIDR: 10.0.0.0/16
  DBInstanceClass: db.t4g.micro|small|medium|large
  CacheNodeType: cache.t4g.micro|small|medium
  ContainerCpu: 256|512|1024|2048|4096
  ContainerMemory: 512|1024|2048|4096|8192
  DesiredCount: 2 (number of tasks)
  MaxCount: 10 (max tasks for auto-scaling)
  CertificateArn: (optional ACM certificate for HTTPS)
```

## GitHub Actions Workflow

The `.github/workflows/deploy.yml` workflow automatically:

1. **Build**: Compiles Swift code on push to `main` or `develop`
2. **Docker**: Builds and pushes image to ECR
3. **Deploy**: Updates ECS service with new image
4. **Verify**: Checks deployment health

### Deployment Triggers

- **Push to `main`** → Deploy to production
- **Push to `develop`** → Deploy to staging
- **Manual trigger** → Choose environment (development/staging/production)

### Workflow Jobs

```
build-and-test
    ↓
build-docker (ECR push)
    ↓
deploy-production (if main branch)
    ↓
notify (send status)
```

## Post-Deployment

### Get Stack Outputs

```bash
aws cloudformation describe-stacks \
  --stack-name afcon-production \
  --query 'Stacks[0].Outputs' \
  --region us-east-1 \
  --output table
```

### Access Endpoints

```bash
# Get ALB DNS name
aws cloudformation describe-stacks \
  --stack-name afcon-production \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' \
  --output text

# Test HTTP endpoint
curl http://<alb-dns>/health

# Test gRPC endpoint (requires grpcurl)
grpcurl -plaintext <alb-dns>:50051 list
```

### Monitor Deployment

```bash
# Watch ECS service
aws ecs describe-services \
  --cluster production-afcon-cluster \
  --services afcon-service \
  --region us-east-1

# View logs
aws logs tail /ecs/production-afcon-server --follow
```

### Database Access

The database is in a private subnet and not publicly accessible. To connect:

```bash
# Option 1: Use ECS Exec (requires enabling execute-command on service)
aws ecs execute-command \
  --cluster production-afcon-cluster \
  --task <task-id> \
  --container afcon-server \
  --command "/bin/bash" \
  --interactive

# Then inside container:
psql $DATABASE_URL

# Option 2: Create bastion host or use AWS Systems Manager Session Manager
```

## Cost Estimation

Approximate monthly costs for production environment (us-east-1):

| Service | Configuration | Monthly Cost |
|---------|--------------|--------------|
| ECS Fargate | 2 tasks (0.5 vCPU, 1GB RAM) | ~$30 |
| RDS PostgreSQL | db.t4g.micro, Multi-AZ | ~$30 |
| ElastiCache Redis | cache.t4g.micro, 2 nodes | ~$25 |
| NAT Gateway | 1 gateway + data transfer | ~$35 |
| ALB | Application Load Balancer | ~$20 |
| Data Transfer | Egress traffic | ~$10 |
| **Total** | | **~$150/month** |

Cost optimization tips:
- Use FARGATE_SPOT for non-production
- Single-AZ RDS for staging
- Reduce task count during off-hours
- Use CloudWatch to identify unused resources

## Troubleshooting

### Stack Creation Failed

```bash
# Check stack events
aws cloudformation describe-stack-events \
  --stack-name afcon-production \
  --region us-east-1 \
  --max-items 20

# Common issues:
# - Insufficient permissions → Add IAM policies
# - Resource limits → Request limit increase
# - Invalid parameters → Check parameter values
```

### Deployment Stuck

```bash
# Check ECS service events
aws ecs describe-services \
  --cluster production-afcon-cluster \
  --services afcon-service \
  --query 'services[0].events' \
  --region us-east-1

# Common issues:
# - Health check failing → Check /health endpoint
# - Cannot pull image → Verify ECR permissions
# - Task failing to start → Check CloudWatch logs
```

### Update Rollback

```bash
# Rollback to previous version
aws ecs update-service \
  --cluster production-afcon-cluster \
  --service afcon-service \
  --force-new-deployment \
  --task-definition afcon-server:<previous-revision>
```

## Cleanup

To delete all resources:

```bash
# Delete CloudFormation stack
aws cloudformation delete-stack \
  --stack-name afcon-production \
  --region us-east-1

# Wait for deletion
aws cloudformation wait stack-delete-complete \
  --stack-name afcon-production \
  --region us-east-1

# Delete ECR images (if needed)
aws ecr delete-repository \
  --repository-name afcon-server \
  --force \
  --region us-east-1

# Delete IAM user
aws iam delete-user --user-name github-actions-deploy
```

**Warning:** This will permanently delete all data including databases and backups.

## Security Best Practices

- Database is in private subnet (not publicly accessible)
- All data encrypted at rest (RDS, Redis)
- IAM roles follow principle of least privilege
- Security groups allow only required traffic
- Secrets stored in AWS Secrets Manager (not environment variables)
- Container images scanned for vulnerabilities
- CloudWatch logs enabled for audit trail

## Support

For issues or questions:
- Check CloudWatch logs: `/ecs/production-afcon-server`
- Review GitHub Actions workflow runs
- Verify AWS Secrets Manager values
- Check security group rules
