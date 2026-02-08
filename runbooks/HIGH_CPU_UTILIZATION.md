# High CPU Utilization Runbook

**Severity:** P2 - High  
**Last Updated:** 2024-12-15  
**Owner:** Platform Engineering Team

---

## Overview

This runbook addresses scenarios where EC2 instances in the Auto Scaling Group experience sustained high CPU utilization (>80%), which can lead to degraded application performance and user experience.

---

## Symptoms

- CloudWatch alarm `3-tier-web-app-high-cpu` in ALARM state
- Increased response times on ALB (TargetResponseTime > 2s)
- User reports of slow page loads
- ASG scaling events triggered

---

## Diagnostic Steps

### Step 1: Confirm Alarm State and Identify Affected Instances

```bash
# Check current alarm state and threshold
aws cloudwatch describe-alarms \
  --alarm-names 3-tier-web-app-high-cpu \
  --query 'MetricAlarms[0].[StateValue,StateReason,Threshold]' \
  --output table

# Get current CPU metrics for the ASG
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=AutoScalingGroupName,Value=3-tier-web-app-asg \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Average Maximum \
  --output table
```

### Step 2: Identify Specific High-CPU Instances

```bash
# List all instances in the ASG with their IDs
INSTANCE_IDS=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names 3-tier-web-app-asg \
  --query 'AutoScalingGroups[0].Instances[*].InstanceId' \
  --output text)

echo "Instances in ASG: $INSTANCE_IDS"

# Get per-instance CPU (last 10 minutes)
for INSTANCE_ID in $INSTANCE_IDS; do
  CPU=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/EC2 \
    --metric-name CPUUtilization \
    --dimensions Name=InstanceId,Value=$INSTANCE_ID \
    --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --period 60 \
    --statistics Average \
    --query 'Datapoints | sort_by(@, &Timestamp) | [-1].Average' \
    --output text)
  echo "$INSTANCE_ID: ${CPU}%"
done
```

### Step 3: Analyze Process-Level CPU Usage

Connect to a high-CPU instance and analyze processes:

```bash
# Connect via Session Manager
INSTANCE_ID="i-xxxxxxxxx"  # Replace with affected instance
aws ssm start-session --target $INSTANCE_ID
```

**Once connected:**

```bash
# Top CPU-consuming processes
top -b -n 1 -o %CPU | head -20

# Check for runaway Python/application processes
ps aux --sort=-%cpu | head -20

# Check for zombie processes
ps aux | grep -w Z

# Memory usage (high memory can cause CPU spikes from swapping)
free -h

# Disk I/O wait (can appear as CPU usage)
iostat -x 1 3

# Check if it's application or system load
pidstat -u 1 5
```

### Step 4: Check Application-Specific Metrics

```bash
# Check request rate to ALB (traffic spike?)
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name RequestCount \
  --dimensions Name=LoadBalancer,Value=$(aws elbv2 describe-load-balancers \
    --names 3-tier-web-app-alb \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text | cut -d'/' -f2-) \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Sum \
  --output table

# Check for slow database queries causing CPU wait
aws logs filter-log-events \
  --log-group-name /aws/ec2/3-tier-web-app \
  --filter-pattern '"slow query" OR "timeout" OR "connection pool"' \
  --start-time $(( $(date +%s) - 1800 ))000 \
  --limit 50
```

### Step 5: Verify ASG Scaling Activity

```bash
# Check if scale-out is happening
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name 3-tier-web-app-asg \
  --max-items 10 \
  --query 'Activities[*].[StartTime,StatusCode,Description]' \
  --output table

# Current vs desired capacity
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names 3-tier-web-app-asg \
  --query 'AutoScalingGroups[0].[MinSize,MaxSize,DesiredCapacity,Instances[*].HealthStatus]' \
  --output json
```

---

## Root Cause Analysis

| Pattern | Likely Cause | Action |
|---------|--------------|--------|
| All instances high CPU, increasing traffic | Legitimate load spike | Verify ASG scaling |
| Single instance high CPU | Runaway process or bad deployment | Terminate instance |
| High CPU with low request count | Application bug (infinite loop) | Check recent deployments |
| High I/O wait | Database slowness or disk issue | Check RDS metrics |
| High CPU after deployment | Code regression | Rollback |

---

## Recovery Actions

### Action 1: Manual Scale-Out (Immediate Relief)

```bash
# Increase desired capacity temporarily
CURRENT=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names 3-tier-web-app-asg \
  --query 'AutoScalingGroups[0].DesiredCapacity' \
  --output text)

NEW_CAPACITY=$((CURRENT + 2))

aws autoscaling set-desired-capacity \
  --auto-scaling-group-name 3-tier-web-app-asg \
  --desired-capacity $NEW_CAPACITY

echo "Scaled from $CURRENT to $NEW_CAPACITY instances"

# Monitor new instances launching
watch -n 10 "aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names 3-tier-web-app-asg \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,LifecycleState,HealthStatus]' \
  --output table"
```

### Action 2: Terminate Specific Unhealthy Instance

```bash
# If a single instance is the problem, terminate it
# ASG will automatically launch a replacement
aws autoscaling terminate-instance-in-auto-scaling-group \
  --instance-id i-xxxxxxxxx \
  --should-decrement-desired-capacity false

echo "Instance terminated. ASG will launch replacement."
```

### Action 3: Kill Runaway Process (Without Instance Termination)

If you identify a specific runaway process:

```bash
# Connect to instance
aws ssm start-session --target i-xxxxxxxxx

# Inside the instance:
# Find the PID of the runaway process
ps aux --sort=-%cpu | head -5

# Kill the process gracefully first
kill -15 <PID>

# If it doesn't stop, force kill
kill -9 <PID>

# Restart the application service
sudo systemctl restart webapp
```

### Action 4: Rollback Recent Deployment

If CPU spike correlates with a deployment:

```bash
# Get launch template versions
aws ec2 describe-launch-template-versions \
  --launch-template-name 3-tier-web-app- \
  --query 'LaunchTemplateVersions[*].[VersionNumber,CreateTime,VersionDescription]' \
  --output table

# Update ASG to use previous version
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name 3-tier-web-app-asg \
  --launch-template LaunchTemplateId=lt-xxxxxxxxx,Version=<previous-version>

# Trigger instance refresh to roll out old version
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name 3-tier-web-app-asg \
  --preferences '{"MinHealthyPercentage": 50}'
```

---

## Prevention

### Implement Target Tracking Scaling

For better automatic response to CPU spikes:

```bash
# This should be in Terraform, but for emergency:
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name 3-tier-web-app-asg \
  --policy-name cpu-target-tracking \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{
    "TargetValue": 70.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ASGAverageCPUUtilization"
    },
    "ScaleOutCooldown": 300,
    "ScaleInCooldown": 300
  }'
```

### Review Instance Type

If CPU issues are frequent, consider upgrading:

```bash
# Current instance type
aws ec2 describe-launch-template-versions \
  --launch-template-name 3-tier-web-app- \
  --versions '$Latest' \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData.InstanceType' \
  --output text

# Options:
# t3.micro  → 2 vCPU (burstable, current)
# t3.small  → 2 vCPU (higher baseline)
# t3.medium → 2 vCPU (even higher baseline)
# m5.large  → 2 vCPU (dedicated, no burst limits)
```

---

## Verification

```bash
# CPU should decrease within 5-10 minutes
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=AutoScalingGroupName,Value=3-tier-web-app-asg \
  --start-time $(date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Average \
  --output table

# Alarm should return to OK
aws cloudwatch describe-alarms \
  --alarm-names 3-tier-web-app-high-cpu \
  --query 'MetricAlarms[0].StateValue' \
  --output text

# Response times should normalize
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name TargetResponseTime \
  --dimensions Name=LoadBalancer,Value=$(aws elbv2 describe-load-balancers \
    --names 3-tier-web-app-alb --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text | cut -d'/' -f2-) \
  --start-time $(date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Average \
  --output table
```

---

## Related Runbooks

- [ASG_SCALING_ISSUES.md](./ASG_SCALING_ISSUES.md) - When scaling doesn't happen
- [ALB_5XX_ERRORS.md](./ALB_5XX_ERRORS.md) - If CPU causes errors
- [RDS_CONNECTION_FAILURE.md](./RDS_CONNECTION_FAILURE.md) - If DB is the bottleneck

---

## References

- [EC2 CPU Credits](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/burstable-credits-baseline-concepts.html)
- [ASG Target Tracking](https://docs.aws.amazon.com/autoscaling/ec2/userguide/as-scaling-target-tracking.html)
- [CloudWatch Metrics for EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/viewing_metrics_with_cloudwatch.html)

