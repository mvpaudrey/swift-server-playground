# AWS Deployment Quick Start Guide

Get your AFCON Swift gRPC server running on AWS in under 30 minutes.

## Prerequisites

### Required Accounts & Tools
- ✅ AWS Account ([sign up](https://aws.amazon.com))
- ✅ AWS CLI installed (`brew install awscli`)
- ✅ Docker Desktop running locally
- ✅ API-Football API key ([get it here](https://www.api-football.com/))

### Optional for Push Notifications
- Apple Developer Account (for APNS)
- Firebase Project (for FCM)

---

## Step 1: Configure AWS CLI (5 minutes)

```bash
# Configure AWS credentials
aws configure

# You'll be prompted for:
# AWS Access Key ID: [Enter your access key]
# AWS Secret Access Key: [Enter your secret key]
# Default region name: us-east-1
# Default output format: json

# Verify configuration
aws sts get-caller-identity
```

**Expected output:**
```json
{
    "UserId": "AIDAI...",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/your-username"
}
```

---

## Step 2: Store API Keys in AWS Secrets Manager (5 minutes)

```bash
# Store API-Football key
aws secretsmanager create-secret \
  --name production-afcon-api-football-key \
  --description "API-Football API key for AFCON server" \
  --secret-string '{"api_key":"YOUR_API_FOOTBALL_KEY_HERE"}' \
  --region us-east-1

# If you have APNS credentials (iOS push notifications)
aws secretsmanager create-secret \
  --name production-afcon-apns \
  --description "Apple Push Notification credentials" \
  --secret-string '{
    "key_id":"YOUR_APNS_KEY_ID",
    "team_id":"YOUR_APPLE_TEAM_ID",
    "topic":"com.yourapp.bundleid"
  }' \
  --region us-east-1

# If you have FCM credentials (Android push notifications)
aws secretsmanager create-secret \
  --name production-afcon-fcm \
  --description "Firebase Cloud Messaging credentials" \
  --secret-string '{"server_key":"YOUR_FCM_SERVER_KEY"}' \
  --region us-east-1
```

**Verify secrets:**
```bash
aws secretsmanager list-secrets --region us-east-1
```

---

## Step 3: Deploy Infrastructure with CloudFormation (15-20 minutes)

### Option A: Deploy Everything (Recommended for Production)

```bash
# Deploy complete stack
aws cloudformation create-stack \
  --stack-name afcon-production \
  --template-body file://infrastructure/cloudformation.yaml \
  --parameters \
    ParameterKey=EnvironmentName,ParameterValue=production \
    ParameterKey=DBInstanceClass,ParameterValue=db.t4g.micro \
    ParameterKey=CacheNodeType,ParameterValue=cache.t4g.micro \
    ParameterKey=DesiredCount,ParameterValue=2 \
  --capabilities CAPABILITY_IAM \
  --region us-east-1

# Monitor deployment progress
aws cloudformation describe-stacks \
  --stack-name afcon-production \
  --query 'Stacks[0].StackStatus' \
  --region us-east-1

# Wait for completion (takes ~15-20 minutes)
aws cloudformation wait stack-create-complete \
  --stack-name afcon-production \
  --region us-east-1
```

### Option B: Deploy Minimal Stack (Development/Testing)

For development, use smaller instance types:

```bash
aws cloudformation create-stack \
  --stack-name afcon-dev \
  --template-body file://infrastructure/cloudformation.yaml \
  --parameters \
    ParameterKey=EnvironmentName,ParameterValue=development \
    ParameterKey=DBInstanceClass,ParameterValue=db.t4g.micro \
    ParameterKey=CacheNodeType,ParameterValue=cache.t4g.micro \
    ParameterKey=DesiredCount,ParameterValue=1 \
  --capabilities CAPABILITY_IAM \
  --region us-east-1
```

**Monitor progress:**
```bash
# Watch stack events
watch -n 5 'aws cloudformation describe-stack-events \
  --stack-name afcon-production \
  --max-items 5 \
  --query "StackEvents[*].[Timestamp,ResourceStatus,ResourceType,LogicalResourceId]" \
  --output table'
```

---

## Step 4: Build and Push Docker Image (10 minutes)

### 4.1: Get ECR Repository URI

```bash
# Get ECR login
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  $(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-1.amazonaws.com

# Get repository URI
ECR_REPO=$(aws cloudformation describe-stacks \
  --stack-name afcon-production \
  --query 'Stacks[0].Outputs[?OutputKey==`ECRRepository`].OutputValue' \
  --output text)

echo "ECR Repository: $ECR_REPO"
```

### 4.2: Build Docker Image (Workaround for Local Build Issues)

Since the local Docker build has version compatibility issues, use this alternative approach:

**Option A: Build on EC2 Instance**

```bash
# Launch a temporary build instance
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t3.medium \
  --key-name your-key-pair \
  --security-group-ids sg-xxxxx \
  --subnet-id subnet-xxxxx \
  --user-data '#!/bin/bash
    yum update -y
    yum install -y docker git
    systemctl start docker
    usermod -a -G docker ec2-user'

# SSH to instance and build there
# (Instance will have Swift 5.9 compatible environment)
```

**Option B: Use GitHub Actions (Recommended)**

The `.github/workflows/deploy.yml` already handles building. Just push to main:

```bash
# Commit your changes
git add .
git commit -m "Deploy AFCON server to AWS"

# Push to trigger deployment
git push origin main
```

**Option C: Use Pre-built Image (Temporary)**

For quick testing, create a minimal Docker image:

```dockerfile
FROM swift:5.9-jammy
WORKDIR /app
COPY . .
RUN swift build -c release
CMD [".build/release/Run", "serve", "--env", "production", "--hostname", "0.0.0.0"]
```

```bash
# Build with Swift 5.9
docker build -f Dockerfile.minimal -t afcon-server:latest .

# Tag and push
docker tag afcon-server:latest $ECR_REPO:latest
docker push $ECR_REPO:latest
```

---

## Step 5: Deploy Application to ECS (5 minutes)

```bash
# Update ECS service to pull latest image
aws ecs update-service \
  --cluster production-afcon-cluster \
  --service afcon-service \
  --force-new-deployment \
  --region us-east-1

# Monitor deployment
aws ecs describe-services \
  --cluster production-afcon-cluster \
  --services afcon-service \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount,Deployments:deployments[0].status}' \
  --region us-east-1

# Wait for service to stabilize
aws ecs wait services-stable \
  --cluster production-afcon-cluster \
  --services afcon-service \
  --region us-east-1
```

---

## Step 6: Get Your Server Endpoints (1 minute)

```bash
# Get Application Load Balancer DNS
ALB_DNS=$(aws cloudformation describe-stacks \
  --stack-name afcon-production \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' \
  --output text)

echo "
🎉 Deployment Complete!

Your AFCON server is now running at:
- HTTP API: http://$ALB_DNS
- gRPC Service: $ALB_DNS:443 (with TLS)
- Health Check: http://$ALB_DNS/health

Test it:
curl http://$ALB_DNS/health
"
```

---

## Step 7: Verify Deployment (2 minutes)

### 7.1: Test HTTP Health Endpoint

```bash
curl http://$ALB_DNS/health
```

**Expected response:**
```json
{"status":"ok"}
```

### 7.2: Test gRPC Service

```bash
# Install grpcurl if not already installed
brew install grpcurl

# List available services
grpcurl -plaintext $ALB_DNS:50051 list

# Test GetLeague method
grpcurl -plaintext \
  -d '{"league_id": 6, "season": 2025}' \
  $ALB_DNS:50051 \
  afcon.AFCONService/GetLeague
```

### 7.3: Check ECS Task Logs

```bash
# View container logs
aws logs tail /ecs/production-afcon-server \
  --follow \
  --region us-east-1
```

---

## Troubleshooting

### Deployment Fails

```bash
# Check CloudFormation events
aws cloudformation describe-stack-events \
  --stack-name afcon-production \
  --region us-east-1 \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
  --output table
```

### Service Won't Start

```bash
# Check ECS task failures
aws ecs describe-tasks \
  --cluster production-afcon-cluster \
  --tasks $(aws ecs list-tasks --cluster production-afcon-cluster --query 'taskArns[0]' --output text) \
  --region us-east-1
```

### Database Connection Issues

```bash
# Verify RDS endpoint
aws rds describe-db-instances \
  --db-instance-identifier production-afcon-db \
  --query 'DBInstances[0].{Endpoint:Endpoint.Address,Status:DBInstanceStatus}' \
  --region us-east-1

# Check security group rules
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=production-afcon-db-sg" \
  --query 'SecurityGroups[0].IpPermissions' \
  --region us-east-1
```

---

## Cost Optimization

### Development Environment
- Use `db.t4g.micro` ($12/month)
- Use `cache.t4g.micro` ($12/month)
- Set `DesiredCount=1` for ECS ($30/month)
- **Total: ~$70-90/month**

### Production Environment
- Use `db.t4g.small` ($35/month)
- Use `cache.t4g.small` ($25/month)
- Set `DesiredCount=2` for ECS ($60/month)
- **Total: ~$150-200/month**

### Cost Reduction Tips
1. Use Reserved Instances (save 30-60%)
2. Stop dev environment when not in use
3. Use Auto Scaling to reduce instances during low traffic
4. Enable CloudWatch Logs retention (7-30 days only)

---

## Cleanup (When Done Testing)

```bash
# Delete CloudFormation stack (this removes all resources)
aws cloudformation delete-stack \
  --stack-name afcon-production \
  --region us-east-1

# Delete secrets
aws secretsmanager delete-secret \
  --secret-id production-afcon-api-football-key \
  --force-delete-without-recovery \
  --region us-east-1

# Verify deletion
aws cloudformation describe-stacks \
  --stack-name afcon-production \
  --region us-east-1
```

---

## Next Steps

### 1. Set Up Custom Domain
- Register domain in Route 53
- Create SSL certificate in ACM
- Update ALB with HTTPS listener
- Point domain to ALB

### 2. Configure Push Notifications
- Upload APNS certificate to Secrets Manager
- Configure FCM credentials
- Test device registration endpoints

### 3. Set Up Monitoring
- Create CloudWatch dashboards
- Configure alarms for errors and high CPU
- Set up SNS notifications

### 4. Enable CI/CD
- Push to GitHub triggers automatic deployment
- See `.github/workflows/deploy.yml`
- Requires adding AWS credentials to GitHub Secrets

---

## Support Resources

- **Full Deployment Guide**: See `DEPLOYMENT.md`
- **CloudFormation Template**: `infrastructure/cloudformation.yaml`
- **Environment Variables**: `.env.example`
- **API Documentation**: API-Football docs
- **AWS Support**: https://console.aws.amazon.com/support/

---

**Ready to deploy? Start with Step 1!** ⬆️
