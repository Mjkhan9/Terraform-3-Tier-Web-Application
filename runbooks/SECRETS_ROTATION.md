# Secrets Rotation Runbook

**Severity:** P3 - Medium  
**Last Updated:** 2024-12-15  
**Owner:** Security Team

---

## Overview

This runbook covers manual and automatic rotation of secrets used by the 3-tier web application, primarily the RDS database credentials stored in AWS Secrets Manager.

---

## When to Rotate

- **Scheduled**: Every 90 days (compliance requirement)
- **Immediate**: After employee departure or suspected compromise
- **Automatic**: When Secrets Manager rotation is enabled

---

## Pre-Rotation Checklist

Before rotating secrets:

1. Verify application is healthy
2. Confirm no deployments in progress
3. Schedule during low-traffic period
4. Have rollback plan ready
5. Notify on-call team

---

## Diagnostic Steps

### Step 1: Identify Current Secrets

```bash
# List all secrets for this project
aws secretsmanager list-secrets \
  --filters Key=tag-key,Values=Project Key=tag-value,Values=3-Tier-Web-Application \
  --query 'SecretList[*].[Name,ARN,LastRotatedDate]' \
  --output table

# Get secret metadata (not the value!)
aws secretsmanager describe-secret \
  --secret-id 3-tier-web-app/db-credentials \
  --query '{
    Name: Name,
    LastRotated: LastRotatedDate,
    RotationEnabled: RotationEnabled,
    VersionIdsToStages: VersionIdsToStages
  }'
```

### Step 2: Check Secret Version Stages

```bash
# AWSCURRENT = active version
# AWSPENDING = during rotation
# AWSPREVIOUS = previous version (for rollback)

aws secretsmanager describe-secret \
  --secret-id 3-tier-web-app/db-credentials \
  --query 'VersionIdsToStages' \
  --output json
```

### Step 3: Verify Application Can Retrieve Secret

```bash
# Connect to an app instance
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names 3-tier-web-app-asg \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text)

aws ssm start-session --target $INSTANCE_ID

# Inside instance, test secret retrieval
aws secretsmanager get-secret-value \
  --secret-id 3-tier-web-app/db-credentials \
  --query 'SecretString' \
  --output text | jq -r '.password' | head -c 5
# Should return first 5 chars of password (for verification only)
```

---

## Manual Rotation Procedure

### Step 1: Generate New Password

```bash
# Generate a strong password
NEW_PASSWORD=$(aws secretsmanager get-random-password \
  --password-length 32 \
  --require-each-included-type \
  --exclude-characters '/@"'\''\\' \
  --output text)

echo "New password generated (first 5 chars): ${NEW_PASSWORD:0:5}..."
```

### Step 2: Update Database Password

```bash
# Get current RDS endpoint
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier 3-tier-web-app-db \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

# Connect to RDS and update password
# Option A: Use master credentials to update app user
PGPASSWORD=$CURRENT_MASTER_PASSWORD psql -h $RDS_ENDPOINT -U admin -d webappdb << EOF
ALTER USER app_user PASSWORD '$NEW_PASSWORD';
EOF

# Option B: Use AWS CLI to modify RDS master password
aws rds modify-db-instance \
  --db-instance-identifier 3-tier-web-app-db \
  --master-user-password "$NEW_PASSWORD" \
  --apply-immediately
```

**Note:** If modifying master password, RDS will have a brief disruption.

### Step 3: Update Secret in Secrets Manager

```bash
# Get current secret
CURRENT_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id 3-tier-web-app/db-credentials \
  --query 'SecretString' \
  --output text)

# Update password in JSON
NEW_SECRET=$(echo $CURRENT_SECRET | jq --arg pw "$NEW_PASSWORD" '.password = $pw')

# Put new version (staged as AWSCURRENT)
aws secretsmanager put-secret-value \
  --secret-id 3-tier-web-app/db-credentials \
  --secret-string "$NEW_SECRET"
```

### Step 4: Restart Application to Pick Up New Credentials

```bash
# Trigger instance refresh (rolling restart)
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name 3-tier-web-app-asg \
  --preferences '{
    "MinHealthyPercentage": 50,
    "InstanceWarmup": 300
  }'

# Monitor refresh
watch -n 10 "aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name 3-tier-web-app-asg \
  --query 'InstanceRefreshes[0].[Status,PercentageComplete]' \
  --output table"
```

---

## Automatic Rotation Setup

### Enable Secrets Manager Rotation

```bash
# Create rotation Lambda (if not exists)
# Note: This is typically done via Terraform

# Enable automatic rotation
aws secretsmanager rotate-secret \
  --secret-id 3-tier-web-app/db-credentials \
  --rotation-lambda-arn arn:aws:lambda:us-east-1:ACCOUNT:function:SecretsManagerRDSRotation \
  --rotation-rules '{
    "AutomaticallyAfterDays": 30
  }'

# Trigger immediate rotation to test
aws secretsmanager rotate-secret \
  --secret-id 3-tier-web-app/db-credentials
```

### Monitor Rotation Status

```bash
# Check if rotation completed successfully
aws secretsmanager describe-secret \
  --secret-id 3-tier-web-app/db-credentials \
  --query '{
    LastRotated: LastRotatedDate,
    NextRotation: NextRotationDate,
    VersionStages: VersionIdsToStages
  }'

# Check CloudWatch for rotation Lambda errors
aws logs filter-log-events \
  --log-group-name /aws/lambda/SecretsManagerRDSRotation \
  --filter-pattern "ERROR" \
  --start-time $(( $(date +%s) - 3600 ))000
```

---

## Rollback Procedure

If rotation fails or breaks the application:

### Step 1: Restore Previous Secret Version

```bash
# Get previous version ID
PREVIOUS_VERSION=$(aws secretsmanager describe-secret \
  --secret-id 3-tier-web-app/db-credentials \
  --query 'VersionIdsToStages | to_entries | [?contains(value, `AWSPREVIOUS`)].key' \
  --output text)

echo "Previous version: $PREVIOUS_VERSION"

# Move AWSCURRENT staging label to previous version
aws secretsmanager update-secret-version-stage \
  --secret-id 3-tier-web-app/db-credentials \
  --version-stage AWSCURRENT \
  --move-to-version-id $PREVIOUS_VERSION \
  --remove-from-version-id $(aws secretsmanager describe-secret \
    --secret-id 3-tier-web-app/db-credentials \
    --query 'VersionIdsToStages | to_entries | [?contains(value, `AWSCURRENT`)].key' \
    --output text)
```

### Step 2: Revert Database Password

```bash
# Get the old password from restored secret
OLD_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id 3-tier-web-app/db-credentials \
  --query 'SecretString' \
  --output text | jq -r '.password')

# Update RDS to use old password
aws rds modify-db-instance \
  --db-instance-identifier 3-tier-web-app-db \
  --master-user-password "$OLD_PASSWORD" \
  --apply-immediately
```

### Step 3: Restart Application

```bash
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name 3-tier-web-app-asg \
  --preferences '{"MinHealthyPercentage": 50}'
```

---

## Verification

```bash
# Test database connectivity through ALB
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names 3-tier-web-app-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

# Health check should pass (tests DB connection)
curl -s http://$ALB_DNS/health | jq

# All targets should be healthy
TG_ARN=$(aws elbv2 describe-target-groups \
  --names 3-tier-web-app-tg \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]' \
  --output table

# No new errors in application logs
aws logs filter-log-events \
  --log-group-name /aws/ec2/3-tier-web-app \
  --filter-pattern '"authentication failed" OR "password" OR "credentials"' \
  --start-time $(( $(date +%s) - 1800 ))000
```

---

## Security Best Practices

1. **Never log passwords** - Use `head -c 5` for partial verification only
2. **Rotate regularly** - 90 days maximum for compliance
3. **Use Secrets Manager rotation** - Not manual processes
4. **Audit secret access** - CloudTrail + Secrets Manager access events
5. **Least privilege** - Applications should only have `secretsmanager:GetSecretValue`

---

## Related Runbooks

- [RDS_CONNECTION_FAILURE.md](./RDS_CONNECTION_FAILURE.md) - If rotation breaks connectivity
- [ALB_5XX_ERRORS.md](./ALB_5XX_ERRORS.md) - Auth errors cause 5XX

---

## References

- [Secrets Manager Rotation](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets.html)
- [RDS Password Rotation](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotate-secrets_turn-on-for-db.html)
- [Secrets Manager Best Practices](https://docs.aws.amazon.com/secretsmanager/latest/userguide/best-practices.html)

