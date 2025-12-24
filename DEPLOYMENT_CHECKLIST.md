# AWS Deployment Checklist

Use this checklist to ensure a successful deployment of your AFCON Swift gRPC server to AWS.

---

## Pre-Deployment (30 minutes)

### ☐ AWS Account Setup
- [ ] AWS account created and verified
- [ ] Billing alerts configured
- [ ] IAM user created with appropriate permissions
- [ ] Access keys generated and stored securely
- [ ] AWS CLI installed (`aws --version`)
- [ ] AWS CLI configured (`aws configure`)
- [ ] Can run: `aws sts get-caller-identity`

### ☐ API Keys and Credentials
- [ ] API-Football API key obtained
- [ ] API-Football subscription active (check limits)
- [ ] Apple Developer Account (if using iOS push notifications)
  - [ ] APNS Key (.p8 file) generated
  - [ ] APNS Key ID noted
  - [ ] Team ID noted
  - [ ] App Bundle ID determined
- [ ] Firebase Project created (if using Android push notifications)
  - [ ] FCM Server Key obtained
  - [ ] Firebase project ID noted

### ☐ Local Environment
- [ ] Docker Desktop installed and running
- [ ] Git repository initialized
- [ ] `.env` file created from `.env.example`
- [ ] All secrets stored securely (not committed to git)
- [ ] `.gitignore` includes `.env`, `secrets/`, `.build/`

### ☐ Code Preparation
- [ ] All code committed to version control
- [ ] Proto files up to date
- [ ] Database migrations tested locally
- [ ] No hardcoded secrets in code
- [ ] Environment variables documented in `.env.example`

---

## Infrastructure Deployment (20 minutes)

### ☐ AWS Secrets Manager
- [ ] API-Football key stored
  ```bash
  aws secretsmanager create-secret \
    --name production-afcon-api-football-key \
    --secret-string '{"api_key":"YOUR_KEY"}' \
    --region us-east-1
  ```
- [ ] APNS credentials stored (if applicable)
  ```bash
  aws secretsmanager create-secret \
    --name production-afcon-apns \
    --secret-string '{"key_id":"...","team_id":"...","topic":"..."}' \
    --region us-east-1
  ```
- [ ] FCM credentials stored (if applicable)
  ```bash
  aws secretsmanager create-secret \
    --name production-afcon-fcm \
    --secret-string '{"server_key":"..."}' \
    --region us-east-1
  ```
- [ ] Secrets verified: `aws secretsmanager list-secrets --region us-east-1`

### ☐ CloudFormation Stack
- [ ] `infrastructure/cloudformation.yaml` reviewed
- [ ] Parameters decided:
  - [ ] Environment name: `production` or `development`
  - [ ] DB instance class: `db.t4g.micro` or `db.t4g.small`
  - [ ] Cache node type: `cache.t4g.micro` or `cache.t4g.small`
  - [ ] Desired ECS task count: `1` (dev) or `2+` (prod)
- [ ] Stack deployment command prepared
- [ ] Stack deployed:
  ```bash
  aws cloudformation create-stack \
    --stack-name afcon-production \
    --template-body file://infrastructure/cloudformation.yaml \
    --parameters ... \
    --capabilities CAPABILITY_IAM \
    --region us-east-1
  ```
- [ ] Stack creation monitored: `aws cloudformation describe-stacks`
- [ ] Stack creation completed (Status: `CREATE_COMPLETE`)

### ☐ Network Configuration
- [ ] VPC created by CloudFormation
- [ ] Subnets created (2 public, 2 private)
- [ ] Security groups configured
- [ ] NAT Gateway created for private subnets
- [ ] Route tables configured

### ☐ Database Setup
- [ ] RDS PostgreSQL instance created
- [ ] Database endpoint accessible from ECS
- [ ] Security group allows connections from ECS
- [ ] Initial database `afcon` created
- [ ] Database credentials stored in Secrets Manager

### ☐ Cache Setup
- [ ] ElastiCache Redis cluster created
- [ ] Redis endpoint accessible from ECS
- [ ] Security group allows connections from ECS

### ☐ Load Balancer
- [ ] Application Load Balancer created
- [ ] Target group created
- [ ] Health check endpoint configured (`/health`)
- [ ] Listeners configured (HTTP:80, gRPC:50051)

---

## Application Deployment (15 minutes)

### ☐ Container Registry
- [ ] ECR repository created by CloudFormation
- [ ] ECR repository URI obtained
- [ ] Docker logged into ECR:
  ```bash
  aws ecr get-login-password --region us-east-1 | \
    docker login --username AWS --password-stdin ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com
  ```

### ☐ Docker Image
- [ ] Dockerfile exists and is correct
- [ ] Docker image built locally (or via GitHub Actions)
- [ ] Image tagged for ECR:
  ```bash
  docker tag afcon-server:latest ECR_REPO:latest
  ```
- [ ] Image pushed to ECR:
  ```bash
  docker push ECR_REPO:latest
  ```
- [ ] Image visible in ECR console

### ☐ ECS Cluster
- [ ] ECS cluster created by CloudFormation
- [ ] Task definition created
- [ ] Task definition includes environment variables
- [ ] Task definition references secrets correctly
- [ ] Task execution role has permissions

### ☐ ECS Service
- [ ] ECS service created by CloudFormation
- [ ] Service connected to load balancer
- [ ] Service desired count matches configuration
- [ ] Service deployment strategy configured
- [ ] Service deployed:
  ```bash
  aws ecs update-service \
    --cluster production-afcon-cluster \
    --service afcon-service \
    --force-new-deployment
  ```
- [ ] Service stable: `aws ecs describe-services`
- [ ] Tasks running: Check running count matches desired count

---

## Verification (10 minutes)

### ☐ Application Health
- [ ] Load balancer DNS obtained
- [ ] Health endpoint responds:
  ```bash
  curl http://ALB_DNS/health
  # Expected: {"status":"ok"}
  ```
- [ ] HTTP API accessible:
  ```bash
  curl http://ALB_DNS/api/v1/league/6/2025
  ```
- [ ] gRPC service accessible:
  ```bash
  grpcurl -plaintext ALB_DNS:50051 list
  ```

### ☐ Database Connectivity
- [ ] Application logs show successful database connection
- [ ] Database tables created automatically
- [ ] Sample data can be inserted and retrieved
- [ ] Check ECS task logs:
  ```bash
  aws logs tail /ecs/production-afcon-server --follow
  ```

### ☐ Redis Connectivity
- [ ] Application logs show successful Redis connection
- [ ] Cache operations working
- [ ] Check cached data in logs

### ☐ External API Integration
- [ ] API-Football API calls succeeding
- [ ] Fixtures being synced
- [ ] No API rate limit errors
- [ ] Check logs for API responses

---

## Post-Deployment (30 minutes)

### ☐ Monitoring Setup
- [ ] CloudWatch Logs configured
- [ ] Log groups created: `/ecs/production-afcon-server`
- [ ] Log retention period set (7-30 days)
- [ ] CloudWatch metrics enabled
- [ ] Key metrics visible:
  - [ ] CPU Utilization
  - [ ] Memory Utilization
  - [ ] Request Count
  - [ ] Database Connections

### ☐ Alarms Configuration
- [ ] High CPU alarm created (>80%)
- [ ] High Memory alarm created (>80%)
- [ ] Database connection alarm created (>80% max)
- [ ] Failed health check alarm created
- [ ] SNS topic created for notifications
- [ ] Email subscribed to SNS topic
- [ ] Alarms tested

### ☐ Auto Scaling
- [ ] ECS service auto-scaling policy created
- [ ] Scale-out policy configured (CPU >70%)
- [ ] Scale-in policy configured (CPU <30%)
- [ ] Min/max task count set appropriately
- [ ] Auto-scaling tested

### ☐ Backup Configuration
- [ ] RDS automated backups enabled
- [ ] Backup retention period set (7-30 days)
- [ ] Backup window configured
- [ ] Point-in-time recovery enabled
- [ ] Manual snapshot taken

---

## Push Notifications (Optional, 1 hour)

### ☐ iOS (APNS)
- [ ] APNS certificate uploaded to Secrets Manager
- [ ] APNS credentials environment variables set
- [ ] Test device registered:
  ```bash
  grpcurl -plaintext -d '{...}' ALB_DNS:50051 afcon.AFCONService/RegisterDevice
  ```
- [ ] Test subscription created
- [ ] Test notification sent successfully
- [ ] Notification received on device

### ☐ Android (FCM)
- [ ] FCM server key stored in Secrets Manager
- [ ] FCM credentials environment variables set
- [ ] Test device registered
- [ ] Test subscription created
- [ ] Test notification sent successfully
- [ ] Notification received on device

---

## CI/CD Setup (Optional, 30 minutes)

### ☐ GitHub Repository
- [ ] Code pushed to GitHub repository
- [ ] Repository visibility set (public/private)
- [ ] Branch protection rules configured for `main`

### ☐ GitHub Actions
- [ ] AWS credentials added to GitHub Secrets:
  - [ ] `AWS_ACCESS_KEY_ID`
  - [ ] `AWS_SECRET_ACCESS_KEY`
- [ ] Workflow file exists: `.github/workflows/deploy.yml`
- [ ] Workflow triggers configured:
  - [ ] Push to `main` → production
  - [ ] Push to `develop` → staging
- [ ] Test push triggers deployment
- [ ] Deployment completes successfully

---

## Security Checklist

### ☐ Access Control
- [ ] IAM roles follow least privilege principle
- [ ] No root account access keys
- [ ] MFA enabled on AWS root account
- [ ] Security groups properly configured
- [ ] Database not publicly accessible
- [ ] Redis not publicly accessible

### ☐ Secrets Management
- [ ] No secrets in code
- [ ] No secrets in git history
- [ ] All secrets in AWS Secrets Manager
- [ ] Secret rotation policy defined
- [ ] Application retrieves secrets at runtime

### ☐ Network Security
- [ ] Load balancer in public subnets
- [ ] ECS tasks in private subnets
- [ ] Database in private subnets
- [ ] Redis in private subnets
- [ ] Security group rules reviewed
- [ ] VPC flow logs enabled (optional)

---

## Cost Verification

### ☐ Resource Review
- [ ] All resources tagged appropriately
- [ ] Resource sizes match requirements
- [ ] No unused resources running
- [ ] Cost estimation reviewed:
  - ECS Fargate: ~$30-70/month
  - RDS PostgreSQL: ~$12-35/month
  - ElastiCache Redis: ~$12-25/month
  - Load Balancer: ~$25/month
  - NAT Gateway: ~$35/month
  - **Total: ~$120-200/month**

### ☐ Cost Optimization
- [ ] Reserved capacity considered for production
- [ ] Auto-scaling configured to reduce costs
- [ ] CloudWatch log retention set appropriately
- [ ] Unused resources cleaned up
- [ ] Billing alerts configured

---

## Documentation

### ☐ Team Documentation
- [ ] Deployment guide shared with team
- [ ] AWS account access documented
- [ ] Runbook created for common tasks
- [ ] Troubleshooting guide available
- [ ] Contact information for support

### ☐ API Documentation
- [ ] gRPC service documentation updated
- [ ] API endpoints documented
- [ ] Request/response examples provided
- [ ] Authentication requirements documented

---

## Testing

### ☐ Functional Testing
- [ ] All HTTP endpoints tested
- [ ] All gRPC methods tested
- [ ] Database operations verified
- [ ] Cache operations verified
- [ ] Error handling tested

### ☐ Load Testing (Optional)
- [ ] Load testing tool configured (e.g., k6, artillery)
- [ ] Baseline performance measured
- [ ] Auto-scaling tested under load
- [ ] Database connection pooling verified

---

## Rollback Plan

### ☐ Rollback Procedures
- [ ] Previous task definition version noted
- [ ] Rollback command prepared:
  ```bash
  aws ecs update-service \
    --cluster production-afcon-cluster \
    --service afcon-service \
    --task-definition afcon-server:PREVIOUS_VERSION
  ```
- [ ] Database migration rollback tested
- [ ] Team trained on rollback procedure

---

## Go-Live Checklist

### ☐ Pre-Launch
- [ ] All checklist items completed
- [ ] Stakeholders notified of deployment
- [ ] Launch time scheduled
- [ ] Support team ready
- [ ] Rollback plan ready

### ☐ Launch
- [ ] Final deployment completed
- [ ] Health checks passing
- [ ] Monitoring dashboards open
- [ ] No critical errors in logs
- [ ] Client apps can connect

### ☐ Post-Launch
- [ ] Monitor for 1 hour after launch
- [ ] Check error rates
- [ ] Verify user traffic
- [ ] Document any issues
- [ ] Send launch confirmation

---

## Quick Reference Commands

```bash
# Check stack status
aws cloudformation describe-stacks --stack-name afcon-production

# Get load balancer DNS
aws cloudformation describe-stacks \
  --stack-name afcon-production \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' \
  --output text

# View ECS service status
aws ecs describe-services \
  --cluster production-afcon-cluster \
  --services afcon-service

# View container logs
aws logs tail /ecs/production-afcon-server --follow

# Force new deployment
aws ecs update-service \
  --cluster production-afcon-cluster \
  --service afcon-service \
  --force-new-deployment

# Rollback deployment
aws ecs update-service \
  --cluster production-afcon-cluster \
  --service afcon-service \
  --task-definition afcon-server:PREVIOUS_VERSION
```

---

## Support

- **AWS Console**: https://console.aws.amazon.com
- **AWS Support**: https://console.aws.amazon.com/support/
- **CloudWatch Logs**: https://console.aws.amazon.com/cloudwatch/
- **ECS Console**: https://console.aws.amazon.com/ecs/

---

**Ready to deploy?** Start checking off items! ✅
