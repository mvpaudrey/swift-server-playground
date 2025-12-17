# AFCON Swift gRPC Server - AWS Deployment Guide

Complete guide for deploying the AFCON Swift server with push notifications to AWS.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Local Development](#local-development)
- [AWS Deployment](#aws-deployment)
- [Push Notifications Setup](#push-notifications-setup)
- [Monitoring & Maintenance](#monitoring--maintenance)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools

```bash
# Install Homebrew (macOS)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required tools
brew install swift
brew install protobuf  # For gRPC code generation
brew install docker
brew install awscli

# Verify installations
swift --version    # Should be 5.9+
protoc --version   # Should be 3.x+
docker --version
aws --version
```

### AWS Account Setup

1. **Create AWS Account**: https://aws.amazon.com
2. **Install AWS CLI**: Already done above
3. **Configure AWS credentials**:
   ```bash
   aws configure
   # Enter your AWS Access Key ID
   # Enter your AWS Secret Access Key
   # Default region: us-east-1
   # Default output format: json
   ```

### API Keys

- **API-Football Key**: Get from https://www.api-football.com/
- **APNS Certificate**: Get from Apple Developer Portal
- **FCM Server Key**: Get from Firebase Console

---

## Local Development

### 1. Clone and Setup

```bash
# Clone repository
cd /path/to/project

# Install dependencies
swift package resolve

# Generate proto files
brew install protobuf
./update-protos.sh
```

### 2. Configure Environment

```bash
# Copy example environment file
cp .env.example .env

# Edit .env with your credentials
nano .env
```

Required variables:
- `API_FOOTBALL_KEY`: Your API-Football API key
- `DATABASE_URL`: PostgreSQL connection string
- Optional: APNS and FCM credentials for push notifications

### 3. Run with Docker Compose

```bash
# Start all services (PostgreSQL, Redis, Server)
docker-compose up -d

# View logs
docker-compose logs -f afcon-server

# Stop services
docker-compose down

# With pgAdmin (database management UI)
docker-compose --profile tools up -d
# Access pgAdmin at http://localhost:5050
```

### 4. Run Locally (Without Docker)

```bash
# Start PostgreSQL
docker-compose up -d postgres

# Run server
swift run

# Server will be available at:
# - HTTP: http://localhost:8080
# - gRPC: localhost:50051
```

### 5. Test the Server

```bash
# Test HTTP endpoint
curl http://localhost:8080/health

# Test gRPC with grpcurl (install: brew install grpcurl)
grpcurl -plaintext localhost:50051 list
grpcurl -plaintext localhost:50051 afcon.AFCONService/GetLeague
```

---

## AWS Deployment

### Step 1: Prepare AWS Infrastructure

#### Option A: Using CloudFormation (Recommended)

```bash
# Deploy the complete infrastructure
aws cloudformation create-stack \
  --stack-name afcon-production \
  --template-body file://infrastructure/cloudformation.yaml \
  --parameters \
    ParameterKey=EnvironmentName,ParameterValue=production \
    ParameterKey=DBInstanceClass,ParameterValue=db.t4g.small \
    ParameterKey=DesiredCount,ParameterValue=2 \
  --capabilities CAPABILITY_IAM \
  --region us-east-1

# Monitor stack creation
aws cloudformation describe-stacks \
  --stack-name afcon-production \
  --query 'Stacks[0].StackStatus'

# Wait for completion (takes ~15-20 minutes)
aws cloudformation wait stack-create-complete \
  --stack-name afcon-production
```

#### Option B: Manual Setup

If you prefer manual setup, create:
1. VPC with public/private subnets
2. RDS PostgreSQL database
3. ElastiCache Redis cluster
4. ECS Cluster with Fargate
5. Application Load Balancer
6. ECR Repository
7. IAM roles and security groups

### Step 2: Configure Secrets

```bash
# Set API-Football key
aws secretsmanager put-secret-value \
  --secret-id production-afcon-api-football-key \
  --secret-string '{"api_key":"YOUR_API_KEY_HERE"}'

# Set APNS credentials (iOS push notifications)
aws secretsmanager put-secret-value \
  --secret-id production-afcon-apns \
  --secret-string '{
    "key_id":"YOUR_APNS_KEY_ID",
    "team_id":"YOUR_TEAM_ID",
    "topic":"com.yourapp.bundleid"
  }'

# Set FCM credentials (Android push notifications)
aws secretsmanager put-secret-value \
  --secret-id production-afcon-fcm \
  --secret-string '{"server_key":"YOUR_FCM_SERVER_KEY"}'
```

### Step 3: Build and Push Docker Image

```bash
# Get ECR login credentials
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

# Build Docker image
docker build -t afcon-server:latest .

# Tag for ECR
docker tag afcon-server:latest \
  ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/afcon-server:latest

# Push to ECR
docker push ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/afcon-server:latest
```

### Step 4: Deploy to ECS

```bash
# Force new deployment
aws ecs update-service \
  --cluster production-afcon-cluster \
  --service afcon-service \
  --force-new-deployment \
  --region us-east-1

# Monitor deployment
aws ecs wait services-stable \
  --cluster production-afcon-cluster \
  --services afcon-service \
  --region us-east-1
```

### Step 5: Get Endpoints

```bash
# Get ALB DNS name
aws cloudformation describe-stacks \
  --stack-name afcon-production \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' \
  --output text

# Example output: afcon-alb-123456789.us-east-1.elb.amazonaws.com
```

**Access your services:**
- HTTP REST API: `http://YOUR_ALB_DNS`
- gRPC Service: `YOUR_ALB_DNS:443` (with TLS) or `:50051` (without)
- Health Check: `http://YOUR_ALB_DNS/health`

---

## Push Notifications Setup

### iOS (APNS)

#### 1. Generate APNS Key

1. Go to https://developer.apple.com/account/resources/authkeys
2. Click "+" to create new key
3. Enable "Apple Push Notifications service (APNs)"
4. Download the `.p8` file
5. Note the Key ID and Team ID

#### 2. Upload to AWS

```bash
# Upload APNS key to S3 or mount as secret
# Option 1: Store in Secrets Manager
aws secretsmanager create-secret \
  --name production-afcon-apns-key \
  --secret-binary fileb://AuthKey_XXXXXXXXXX.p8

# Option 2: Store in ECS task volume (recommended)
# Copy .p8 file to secrets/ directory locally
# Mount secrets volume in docker-compose.yml (already configured)
```

#### 3. Configure Environment

Update CloudFormation stack or ECS task definition with:
- `APNS_KEY_ID`: Your APNS Key ID
- `APNS_TEAM_ID`: Your Apple Team ID
- `APNS_TOPIC`: Your app's bundle identifier
- `APNS_ENVIRONMENT`: `sandbox` or `production`
- `APNS_KEY_PATH`: Path to .p8 file

### Android (FCM)

#### 1. Create Firebase Project

1. Go to https://console.firebase.google.com/
2. Create new project or select existing
3. Add Android app with package name
4. Download `google-services.json`

#### 2. Get Server Key

1. Go to Project Settings → Cloud Messaging
2. Copy the "Server key"
3. Store in AWS Secrets Manager (done in Step 2 above)

#### 3. Test Notifications

```bash
# Register a test device
grpcurl -plaintext \
  -d '{
    "user_id": "test-user-123",
    "device_token": "YOUR_DEVICE_TOKEN",
    "platform": "ios",
    "language": "en"
  }' \
  YOUR_ALB_DNS:50051 \
  afcon.AFCONService/RegisterDevice

# Subscribe to AFCON 2025
grpcurl -plaintext \
  -d '{
    "device_uuid": "DEVICE_UUID_FROM_RESPONSE",
    "subscriptions": [{
      "league_id": 6,
      "season": 2025,
      "team_id": 0,
      "preferences": {
        "notify_goals": true,
        "notify_match_start": true,
        "notify_match_end": true,
        "notify_red_cards": true,
        "match_start_minutes_before": 15
      }
    }]
  }' \
  YOUR_ALB_DNS:50051 \
  afcon.AFCONService/UpdateSubscriptions
```

---

## CI/CD with GitHub Actions

### Setup

1. **Add GitHub Secrets**:
   - Go to Repository → Settings → Secrets and variables → Actions
   - Add:
     - `AWS_ACCESS_KEY_ID`
     - `AWS_SECRET_ACCESS_KEY`

2. **Configure Workflow**:
   - File: `.github/workflows/deploy.yml` (already created)
   - Triggers on push to `main` (production) or `develop` (staging)

3. **Deployment Process**:
   - Push to `main` → Automatic deployment to production
   - Push to `develop` → Automatic deployment to staging
   - Pull requests → Build and test only

### Manual Deployment

```bash
# Trigger manual deployment via GitHub Actions UI
# Go to Actions → Deploy to AWS ECS → Run workflow
# Select environment: development/staging/production
```

---

## Monitoring & Maintenance

### CloudWatch Logs

```bash
# View ECS container logs
aws logs tail /ecs/production-afcon-server --follow

# View RDS logs
aws rds describe-db-log-files \
  --db-instance-identifier production-afcon-db
```

### CloudWatch Metrics

Access in AWS Console:
- ECS → Clusters → production-afcon-cluster → Metrics
- RDS → Databases → production-afcon-db → Monitoring

Key metrics:
- CPU Utilization (should be < 70%)
- Memory Utilization
- Database Connections
- ALB Request Count
- gRPC Request Count

### Health Checks

```bash
# Check HTTP health
curl http://YOUR_ALB_DNS/health

# Check ECS service status
aws ecs describe-services \
  --cluster production-afcon-cluster \
  --services afcon-service \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'
```

### Database Maintenance

```bash
# Connect to RDS via bastion or port forwarding
psql -h YOUR_RDS_ENDPOINT -U postgres -d afcon

# Check database size
SELECT pg_size_pretty(pg_database_size('afcon'));

# Check notification history
SELECT COUNT(*), status FROM notification_history
GROUP BY status;

# Clean old notification history (older than 30 days)
DELETE FROM notification_history
WHERE sent_at < NOW() - INTERVAL '30 days';
```

### Scaling

```bash
# Manual scaling
aws ecs update-service \
  --cluster production-afcon-cluster \
  --service afcon-service \
  --desired-count 5

# View auto-scaling configuration
aws application-autoscaling describe-scaling-policies \
  --service-namespace ecs
```

---

## Troubleshooting

### Common Issues

#### 1. Container Not Starting

```bash
# Check ECS task logs
aws ecs describe-tasks \
  --cluster production-afcon-cluster \
  --tasks TASK_ID

# Check stopped task reason
aws logs get-log-events \
  --log-group-name /ecs/production-afcon-server \
  --log-stream-name ecs/afcon-server/TASK_ID
```

#### 2. Database Connection Issues

- Verify security groups allow ECS → RDS on port 5432
- Check DATABASE_URL environment variable
- Verify RDS instance is in same VPC

```bash
# Test database connectivity from ECS task
aws ecs execute-command \
  --cluster production-afcon-cluster \
  --task TASK_ID \
  --container afcon-server \
  --command "curl -v telnet://RDS_ENDPOINT:5432" \
  --interactive
```

#### 3. Push Notifications Not Working

**iOS (APNS)**:
- Verify APNS key (.p8) is correctly mounted
- Check APNS_ENVIRONMENT (sandbox vs production)
- Verify APNS_TOPIC matches app bundle ID
- Check CloudWatch logs for APNS errors

**Android (FCM)**:
- Verify FCM_SERVER_KEY is correct
- Test with FCM testing tool
- Check device token validity

```bash
# Test notification manually
aws logs filter-log-events \
  --log-group-name /ecs/production-afcon-server \
  --filter-pattern "notification" \
  --start-time $(date -u -d '5 minutes ago' +%s)000
```

#### 4. High CPU/Memory Usage

```bash
# Check resource utilization
aws ecs describe-services \
  --cluster production-afcon-cluster \
  --services afcon-service

# Scale up if needed
aws ecs update-service \
  --cluster production-afcon-cluster \
  --service afcon-service \
  --desired-count 4

# Or increase task resources
# Edit CloudFormation template:
# - ContainerCpu: 1024 (1 vCPU)
# - ContainerMemory: 2048 (2 GB)
```

---

## Cost Optimization

### Estimated Monthly Costs (Medium Scale: 1K-50K users)

| Service | Configuration | Monthly Cost |
|---------|--------------|--------------|
| ECS Fargate | 2 tasks (0.5 vCPU, 1GB) | ~$67 |
| RDS PostgreSQL | db.t4g.micro | ~$18 |
| ElastiCache Redis | 2x cache.t4g.micro | ~$25 |
| Application Load Balancer | Standard | ~$26 |
| NAT Gateway | 1 gateway + 50GB data | ~$35 |
| Data Transfer | ~50GB outbound | ~$15 |
| CloudWatch | Logs + metrics | ~$3 |
| SNS | 15M notifications/month | ~$7 |
| **Total** | | **~$196/month** |

### Cost Reduction Strategies

1. **Use Reserved Capacity**: Save 30-60% on RDS and ElastiCache
2. **Optimize Cache**: Aggressive caching reduces database load
3. **Use Spot Instances**: Use FARGATE_SPOT for non-critical tasks
4. **Batch Notifications**: Reduce SNS costs
5. **CloudFront CDN**: Cache static assets
6. **Delete Old Logs**: Retain logs for 7-30 days only

---

## Rollback Procedure

```bash
# Via GitHub Actions
# Go to Actions → Deploy to AWS ECS → Run workflow
# Select "rollback" option

# Manual rollback
aws ecs update-service \
  --cluster production-afcon-cluster \
  --service afcon-service \
  --task-definition afcon-server:PREVIOUS_REVISION \
  --force-new-deployment
```

---

## Support & Resources

- **AWS Documentation**: https://docs.aws.amazon.com/ecs/
- **Swift Documentation**: https://swift.org/documentation/
- **gRPC Swift**: https://github.com/grpc/grpc-swift
- **APNSwift**: https://github.com/swift-server-community/APNSwift
- **API-Football**: https://www.api-football.com/documentation

---

**Deployment complete! 🚀**

Your AFCON Swift gRPC server with push notifications is now running on AWS ECS.
