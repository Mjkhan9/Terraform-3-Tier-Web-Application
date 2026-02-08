# ALB 5XX Errors Runbook

**Severity:** P1 - Critical  
**Last Updated:** 2024-12-15  
**Owner:** Platform Engineering Team

---

## Overview

This runbook addresses HTTP 5XX errors returned by the Application Load Balancer. These errors indicate server-side failures and directly impact user experience.

---

## Error Types

| Error Code | Source | Meaning |
|------------|--------|---------|
| 502 Bad Gateway | ALB | Target returned invalid response |
| 503 Service Unavailable | ALB | No healthy targets registered |
| 504 Gateway Timeout | ALB | Target didn't respond in time |
| 500 Internal Server Error | Target | Application error |

---

## Symptoms

- CloudWatch alarm `3-tier-web-app-alb-5xx-errors` in ALARM state
- Users seeing error pages
- Elevated error rates in application monitoring
- Health check failures

---

## Diagnostic Steps

### Step 1: Quantify the Error Rate

```bash
# Get 5XX count over last hour (5-minute intervals)
ALB_ARN_SUFFIX=$(aws elbv2 describe-load-balancers \
  --names 3-tier-web-app-alb \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text | sed 's/.*:loadbalancer\///')

aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name HTTPCode_Target_5XX_Count \
  --dimensions Name=LoadBalancer,Value=$ALB_ARN_SUFFIX \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Sum \
  --output table

# Compare to total requests
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name RequestCount \
  --dimensions Name=LoadBalancer,Value=$ALB_ARN_SUFFIX \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Sum \
  --output table
```

### Step 2: Check Target Health Status

```bash
# Get target group ARN
TG_ARN=$(aws elbv2 describe-target-groups \
  --names 3-tier-web-app-tg \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

# Check health of all targets
aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason,TargetHealth.Description]' \
  --output table
```

**Interpret results:**

| State | Reason | Action |
|-------|--------|--------|
| healthy | - | Target is OK |
| unhealthy | Target.ResponseCodeMismatch | App returning non-200 on /health |
| unhealthy | Target.Timeout | App not responding in time |
| unhealthy | Target.FailedHealthChecks | Multiple consecutive failures |
| draining | - | Instance being deregistered (normal during deployments) |

### Step 3: Distinguish ALB vs Target Errors

```bash
# ELB-generated 5XX (ALB's fault - no healthy targets, etc.)
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name HTTPCode_ELB_5XX_Count \
  --dimensions Name=LoadBalancer,Value=$ALB_ARN_SUFFIX \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Sum \
  --output table

# Target-generated 5XX (application's fault)
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name HTTPCode_Target_5XX_Count \
  --dimensions Name=LoadBalancer,Value=$ALB_ARN_SUFFIX \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Sum \
  --output table
```

**If ELB 5XX > 0:** Problem is at ALB level (no healthy targets)
**If Target 5XX > 0:** Problem is in application code

### Step 4: Analyze Application Logs

```bash
# Get recent error logs
aws logs filter-log-events \
  --log-group-name /aws/ec2/3-tier-web-app \
  --filter-pattern '?"ERROR" ?"Exception" ?"Traceback" ?"500"' \
  --start-time $(( $(date +%s) - 1800 ))000 \
  --limit 100 \
  --query 'events[*].[timestamp,message]' \
  --output text | head -50

# Check for specific error patterns
aws logs filter-log-events \
  --log-group-name /aws/ec2/3-tier-web-app \
  --filter-pattern '"Internal Server Error"' \
  --start-time $(( $(date +%s) - 1800 ))000 \
  --limit 20
```

### Step 5: Check ALB Access Logs (Detailed Request Analysis)

```bash
# Get today's ALB logs from S3
BUCKET=$(aws s3 ls | grep 3-tier-web-app | grep logs | awk '{print $3}')
DATE=$(date +%Y/%m/%d)

# List recent log files
aws s3 ls s3://$BUCKET/alb/AWSLogs/ --recursive | tail -10

# Download and analyze a recent log file
aws s3 cp s3://$BUCKET/alb/AWSLogs/<account-id>/elasticloadbalancing/us-east-1/$DATE/<logfile>.gz ./

gunzip <logfile>.gz

# Filter for 5XX responses
awk '$9 >= 500' <logfile> | head -20

# Find most common error-causing URLs
awk '$9 >= 500 {print $13}' <logfile> | sort | uniq -c | sort -rn | head -10
```

---

## Recovery Actions

### Action 1: Restart Unhealthy Instances

If specific instances are unhealthy:

```bash
# Get unhealthy instance IDs
UNHEALTHY=$(aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --query 'TargetHealthDescriptions[?TargetHealth.State!=`healthy`].Target.Id' \
  --output text)

for INSTANCE in $UNHEALTHY; do
  echo "Terminating unhealthy instance: $INSTANCE"
  aws autoscaling terminate-instance-in-auto-scaling-group \
    --instance-id $INSTANCE \
    --should-decrement-desired-capacity false
done

echo "ASG will launch replacements automatically"
```

### Action 2: Force Instance Refresh (All Instances)

If errors are widespread:

```bash
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name 3-tier-web-app-asg \
  --preferences '{
    "MinHealthyPercentage": 50,
    "InstanceWarmup": 300,
    "CheckpointPercentages": [33, 66, 100],
    "CheckpointDelay": 60
  }'

# Monitor progress
watch -n 15 "aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name 3-tier-web-app-asg \
  --query 'InstanceRefreshes[0].[Status,PercentageComplete,StatusReason]' \
  --output table"
```

### Action 3: Fix Database Connectivity (If DB-Related)

If logs show database errors:

```bash
# Test RDS availability
aws rds describe-db-instances \
  --db-instance-identifier 3-tier-web-app-db \
  --query 'DBInstances[0].[DBInstanceStatus,Endpoint.Address]' \
  --output text

# If RDS is down, see RDS_CONNECTION_FAILURE.md runbook
```

### Action 4: Rollback Deployment

If errors started after a deployment:

```bash
# Check when errors started
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name HTTPCode_Target_5XX_Count \
  --dimensions Name=LoadBalancer,Value=$ALB_ARN_SUFFIX \
  --start-time $(date -u -d '6 hours ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Sum \
  --output table

# Rollback to previous launch template version
aws ec2 describe-launch-template-versions \
  --launch-template-name 3-tier-web-app- \
  --query 'LaunchTemplateVersions[*].[VersionNumber,CreateTime]' \
  --output table

# Set ASG to use previous version
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name 3-tier-web-app-asg \
  --launch-template LaunchTemplateId=lt-xxxxxxxxx,Version=<N-1>

# Refresh instances
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name 3-tier-web-app-asg \
  --preferences '{"MinHealthyPercentage": 50}'
```

### Action 5: Emergency Capacity Increase

```bash
# Double capacity immediately
CURRENT=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names 3-tier-web-app-asg \
  --query 'AutoScalingGroups[0].DesiredCapacity' \
  --output text)

aws autoscaling set-desired-capacity \
  --auto-scaling-group-name 3-tier-web-app-asg \
  --desired-capacity $((CURRENT * 2))
```

---

## Verification

```bash
# 5XX rate should decrease
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name HTTPCode_Target_5XX_Count \
  --dimensions Name=LoadBalancer,Value=$ALB_ARN_SUFFIX \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Sum \
  --output table

# All targets should be healthy
aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]' \
  --output table

# Test endpoint directly
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names 3-tier-web-app-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

for i in {1..10}; do
  curl -s -o /dev/null -w "%{http_code}\n" http://$ALB_DNS/health
  sleep 1
done

# Alarm should return to OK
aws cloudwatch describe-alarms \
  --alarm-names 3-tier-web-app-alb-5xx-errors \
  --query 'MetricAlarms[0].StateValue' \
  --output text
```

---

## Post-Incident Actions

1. **Root Cause Analysis**: Identify what caused the errors
2. **Update Health Checks**: If too aggressive, adjust thresholds
3. **Add Monitoring**: Set up more granular alerting
4. **Document**: Update this runbook with lessons learned

---

## Related Runbooks

- [RDS_CONNECTION_FAILURE.md](./RDS_CONNECTION_FAILURE.md) - Database connectivity
- [HIGH_CPU_UTILIZATION.md](./HIGH_CPU_UTILIZATION.md) - Performance issues
- [ASG_SCALING_ISSUES.md](./ASG_SCALING_ISSUES.md) - Capacity problems

---

## References

- [ALB Troubleshooting](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-troubleshooting.html)
- [HTTP 5XX Error Codes](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-cloudwatch-metrics.html)
- [ALB Access Logs](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-access-logs.html)

