# ASG Scaling Issues Runbook

**Severity:** P2 - High  
**Last Updated:** 2024-12-15  
**Owner:** Platform Engineering Team

---

## Overview

This runbook addresses scenarios where the Auto Scaling Group fails to scale out (add instances) or scale in (remove instances) as expected. Issues include stuck scaling activities, instances failing to launch, or scaling policies not triggering.

---

## Symptoms

- High CPU/request rate but no new instances launching
- Instances stuck in "Pending" state
- Scaling activities showing "Failed" status
- CloudWatch alarms firing but no scaling response
- Instances being terminated unexpectedly

---

## Diagnostic Steps

### Step 1: Check Current ASG State

```bash
# Get comprehensive ASG status
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names 3-tier-web-app-asg \
  --query 'AutoScalingGroups[0].{
    MinSize: MinSize,
    MaxSize: MaxSize,
    DesiredCapacity: DesiredCapacity,
    InstanceCount: length(Instances),
    InstanceStates: Instances[*].{Id: InstanceId, State: LifecycleState, Health: HealthStatus},
    SuspendedProcesses: SuspendedProcesses
  }' \
  --output json
```

**Key checks:**
- Is `DesiredCapacity` at `MaxSize`? → Already at max, can't scale up
- Are there `SuspendedProcesses`? → Scaling might be disabled
- Instance states should be `InService`, not `Pending` or `Terminating`

### Step 2: Review Recent Scaling Activities

```bash
# Get last 20 scaling activities
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name 3-tier-web-app-asg \
  --max-items 20 \
  --query 'Activities[*].{
    Time: StartTime,
    Status: StatusCode,
    Cause: Cause,
    Description: Description,
    StatusMessage: StatusMessage
  }' \
  --output table
```

**Common failure causes:**
- `InsufficientInstanceCapacity`: AWS doesn't have instances available
- `VPCResourceNotSpecified`: Subnet or security group issue
- `InvalidAMI.NotFound`: AMI was deleted
- `UnauthorizedOperation`: IAM permission issue

### Step 3: Check Scaling Policies

```bash
# List scaling policies
aws autoscaling describe-policies \
  --auto-scaling-group-name 3-tier-web-app-asg \
  --query 'ScalingPolicies[*].{
    Name: PolicyName,
    Type: PolicyType,
    Adjustment: ScalingAdjustment,
    Cooldown: Cooldown,
    Enabled: Enabled
  }' \
  --output table

# Check if policies are attached to alarms
aws cloudwatch describe-alarms \
  --alarm-name-prefix 3-tier-web-app \
  --query 'MetricAlarms[*].{
    Name: AlarmName,
    State: StateValue,
    Actions: AlarmActions
  }' \
  --output table
```

### Step 4: Verify Launch Template

```bash
# Get current launch template version
LT_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names 3-tier-web-app-asg \
  --query 'AutoScalingGroups[0].LaunchTemplate.LaunchTemplateId' \
  --output text)

LT_VERSION=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names 3-tier-web-app-asg \
  --query 'AutoScalingGroups[0].LaunchTemplate.Version' \
  --output text)

echo "Launch Template: $LT_ID, Version: $LT_VERSION"

# Verify the template is valid
aws ec2 describe-launch-template-versions \
  --launch-template-id $LT_ID \
  --versions $LT_VERSION \
  --query 'LaunchTemplateVersions[0].{
    AMI: LaunchTemplateData.ImageId,
    InstanceType: LaunchTemplateData.InstanceType,
    SecurityGroups: LaunchTemplateData.SecurityGroupIds,
    Profile: LaunchTemplateData.IamInstanceProfile
  }' \
  --output json

# Verify AMI exists and is available
AMI_ID=$(aws ec2 describe-launch-template-versions \
  --launch-template-id $LT_ID \
  --versions $LT_VERSION \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData.ImageId' \
  --output text)

aws ec2 describe-images \
  --image-ids $AMI_ID \
  --query 'Images[0].[State,Description]' \
  --output text
```

### Step 5: Check Subnet Capacity

```bash
# Get subnets used by ASG
SUBNET_IDS=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names 3-tier-web-app-asg \
  --query 'AutoScalingGroups[0].VPCZoneIdentifier' \
  --output text | tr ',' '\n')

# Check available IPs in each subnet
for SUBNET in $SUBNET_IDS; do
  aws ec2 describe-subnets \
    --subnet-ids $SUBNET \
    --query 'Subnets[0].{
      SubnetId: SubnetId,
      AZ: AvailabilityZone,
      AvailableIPs: AvailableIpAddressCount,
      CIDR: CidrBlock
    }' \
    --output table
done
```

**If AvailableIPs is low (<5):** Subnet is exhausted, instances can't launch.

### Step 6: Check for Suspended Processes

```bash
# List any suspended scaling processes
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names 3-tier-web-app-asg \
  --query 'AutoScalingGroups[0].SuspendedProcesses' \
  --output table
```

**Common suspended processes:**
- `Launch`: Prevents new instances
- `Terminate`: Prevents instance termination
- `HealthCheck`: Disables health checking
- `ReplaceUnhealthy`: Won't replace failed instances

---

## Recovery Actions

### Action 1: Resume Suspended Processes

```bash
aws autoscaling resume-processes \
  --auto-scaling-group-name 3-tier-web-app-asg

# Or resume specific processes
aws autoscaling resume-processes \
  --auto-scaling-group-name 3-tier-web-app-asg \
  --scaling-processes Launch Terminate HealthCheck ReplaceUnhealthy
```

### Action 2: Increase Max Capacity (If at Limit)

```bash
# Increase max size temporarily
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name 3-tier-web-app-asg \
  --max-size 8

# Then manually set desired capacity
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name 3-tier-web-app-asg \
  --desired-capacity 6

# Note: Update terraform.tfvars to make permanent
```

### Action 3: Fix Launch Template Issues

If AMI is unavailable, update to latest Amazon Linux 2:

```bash
# Get latest Amazon Linux 2 AMI
NEW_AMI=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
            "Name=state,Values=available" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
  --output text)

echo "New AMI: $NEW_AMI"

# Create new launch template version
aws ec2 create-launch-template-version \
  --launch-template-id $LT_ID \
  --source-version $LT_VERSION \
  --launch-template-data "{\"ImageId\":\"$NEW_AMI\"}" \
  --version-description "Updated AMI $(date +%Y%m%d)"

# Update ASG to use latest version
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name 3-tier-web-app-asg \
  --launch-template LaunchTemplateId=$LT_ID,Version='$Latest'

# Trigger instance refresh
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name 3-tier-web-app-asg
```

### Action 4: Handle Capacity Issues

If AWS capacity is unavailable in your AZs:

```bash
# Check spot capacity (alternative to on-demand)
aws ec2 describe-spot-instance-requests \
  --filters "Name=state,Values=active,open" \
  --query 'SpotInstanceRequests[*].[SpotInstanceRequestId,State,Status.Code]' \
  --output table

# Try a different instance type (temporarily)
# Modify launch template
aws ec2 create-launch-template-version \
  --launch-template-id $LT_ID \
  --source-version $LT_VERSION \
  --launch-template-data '{"InstanceType":"t3.small"}' \
  --version-description "Fallback instance type"
```

### Action 5: Manual Instance Launch (Emergency)

If ASG is completely stuck:

```bash
# Launch instance manually with the same config
aws ec2 run-instances \
  --launch-template LaunchTemplateId=$LT_ID,Version=$LT_VERSION \
  --subnet-id subnet-xxxxxxxxx \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=3-tier-web-app-manual}]'

# Attach to target group manually
INSTANCE_ID=i-xxxxxxxxx
TG_ARN=$(aws elbv2 describe-target-groups \
  --names 3-tier-web-app-tg \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

aws elbv2 register-targets \
  --target-group-arn $TG_ARN \
  --targets Id=$INSTANCE_ID
```

**Warning:** Manual instances won't be managed by ASG. Use only for emergency.

### Action 6: Reset Cooldown (If Scaling Blocked)

```bash
# Check if cooldown is blocking scaling
aws autoscaling describe-policies \
  --auto-scaling-group-name 3-tier-web-app-asg \
  --query 'ScalingPolicies[*].[PolicyName,Cooldown]' \
  --output table

# Temporarily reduce cooldown
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name 3-tier-web-app-asg \
  --policy-name 3-tier-web-app-scale-up \
  --adjustment-type ChangeInCapacity \
  --scaling-adjustment 1 \
  --cooldown 60  # Reduced from 300
```

---

## Verification

```bash
# Instances should be launching
watch -n 10 "aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names 3-tier-web-app-asg \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,LifecycleState,HealthStatus]' \
  --output table"

# Scaling activities should show Success
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name 3-tier-web-app-asg \
  --max-items 5 \
  --query 'Activities[*].[StartTime,StatusCode,Description]' \
  --output table

# Targets should register as healthy
TG_ARN=$(aws elbv2 describe-target-groups \
  --names 3-tier-web-app-tg \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]' \
  --output table
```

---

## Prevention

### Implement Predictive Scaling

```bash
# Enable predictive scaling for anticipated load patterns
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name 3-tier-web-app-asg \
  --policy-name predictive-scaling \
  --policy-type PredictiveScaling \
  --predictive-scaling-configuration '{
    "MetricSpecifications": [{
      "TargetValue": 70,
      "PredefinedMetricPairSpecification": {
        "PredefinedMetricType": "ASGCPUUtilization"
      }
    }],
    "Mode": "ForecastAndScale",
    "SchedulingBufferTime": 300
  }'
```

### Use Mixed Instance Types

In Terraform, configure instance type diversity:

```hcl
mixed_instances_policy {
  launch_template {
    launch_template_specification {
      launch_template_id = aws_launch_template.app.id
    }
    override {
      instance_type = "t3.micro"
    }
    override {
      instance_type = "t3.small"
    }
    override {
      instance_type = "t2.micro"
    }
  }
}
```

---

## Related Runbooks

- [HIGH_CPU_UTILIZATION.md](./HIGH_CPU_UTILIZATION.md) - CPU triggers scaling
- [ALB_5XX_ERRORS.md](./ALB_5XX_ERRORS.md) - Errors from insufficient capacity
- [RDS_CONNECTION_FAILURE.md](./RDS_CONNECTION_FAILURE.md) - Database bottlenecks

---

## References

- [ASG Troubleshooting](https://docs.aws.amazon.com/autoscaling/ec2/userguide/ts-as-capacity.html)
- [Launch Template Versioning](https://docs.aws.amazon.com/autoscaling/ec2/userguide/LaunchTemplates.html)
- [Scaling Cooldowns](https://docs.aws.amazon.com/autoscaling/ec2/userguide/Cooldown.html)

