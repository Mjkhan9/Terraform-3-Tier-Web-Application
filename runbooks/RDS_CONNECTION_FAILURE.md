# RDS Connection Failure Runbook

**Severity:** P1 - Critical  
**Last Updated:** 2024-12-15  
**Owner:** Platform Engineering Team

---

## Overview

This runbook covers diagnosing and resolving PostgreSQL RDS connection failures from the application tier. Common causes include security group misconfiguration, RDS instance state issues, and network connectivity problems.

---

## Symptoms

- Application returning HTTP 500 errors
- Health check failures on `/health` endpoint
- CloudWatch alarm `3-tier-web-app-alb-unhealthy-hosts` in ALARM state
- Application logs showing `connection refused` or `timeout` errors

---

## Diagnostic Steps

### Step 1: Verify RDS Instance Status

First, confirm the RDS instance is running and accessible:

```bash
aws rds describe-db-instances \
  --db-instance-identifier 3-tier-web-app-db \
  --query 'DBInstances[0].[DBInstanceStatus,Endpoint.Address,Endpoint.Port,AvailabilityZone]' \
  --output table
```

**Expected output:**
```
-----------------------------------------------------------------
|                    DescribeDBInstances                        |
+------------+----------------------------------------+------+--------+
|  available | 3-tier-web-app-db.xxxxx.us-east-1.rds | 5432 | us-east-1a |
+------------+----------------------------------------+------+--------+
```

**If status is NOT `available`:**
- `backing-up`: Wait for backup to complete (check maintenance window)
- `modifying`: Check for pending modifications
- `stopped`: Start the instance (see Recovery Actions)
- `failed`: Escalate to AWS Support

### Step 2: Verify Security Group Rules

Check that the RDS security group allows inbound traffic from the application security group:

```bash
# Get RDS security group ID
RDS_SG=$(aws rds describe-db-instances \
  --db-instance-identifier 3-tier-web-app-db \
  --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text)

echo "RDS Security Group: $RDS_SG"

# Get App security group ID (source of allowed traffic)
APP_SG=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=*3-tier-web-app*app*" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

echo "App Security Group: $APP_SG"

# Check inbound rules on RDS security group
aws ec2 describe-security-groups \
  --group-ids $RDS_SG \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`5432`]' \
  --output json
```

**Expected output should include:**
```json
[
  {
    "FromPort": 5432,
    "ToPort": 5432,
    "IpProtocol": "tcp",
    "UserIdGroupPairs": [
      {
        "GroupId": "sg-xxxxxxxxx"  # Should match APP_SG
      }
    ]
  }
]
```

**If APP_SG is not in the allowed sources:** See Recovery Actions - Add Security Group Rule.

### Step 3: Test Network Connectivity from App Tier

Connect to an app tier EC2 instance via Session Manager and test PostgreSQL port reachability:

```bash
# Get an instance ID from the ASG
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names 3-tier-web-app-asg \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text)

echo "Connecting to instance: $INSTANCE_ID"

# Start Session Manager session
aws ssm start-session --target $INSTANCE_ID
```

**Once connected to the instance, run:**

```bash
# Get RDS endpoint from instance metadata or environment
RDS_ENDPOINT="3-tier-web-app-db.xxxxx.us-east-1.rds.amazonaws.com"

# Test TCP connectivity to PostgreSQL port
nc -zv $RDS_ENDPOINT 5432

# If nc not available, use timeout with bash
timeout 5 bash -c "echo > /dev/tcp/$RDS_ENDPOINT/5432" && echo "Port open" || echo "Port closed/timeout"

# Test DNS resolution
nslookup $RDS_ENDPOINT

# Check routing
traceroute -T -p 5432 $RDS_ENDPOINT
```

**Expected output:**
```
Connection to 3-tier-web-app-db.xxxxx.us-east-1.rds.amazonaws.com 5432 port [tcp/postgresql] succeeded!
```

### Step 4: Check Application Logs for Specific Errors

```bash
# Get recent connection errors from CloudWatch Logs
aws logs filter-log-events \
  --log-group-name /aws/ec2/3-tier-web-app \
  --filter-pattern "?connection ?refused ?timeout ?postgres" \
  --start-time $(( $(date +%s) - 3600 ))000 \
  --limit 20 \
  --query 'events[*].[timestamp,message]' \
  --output table
```

**Common error patterns and causes:**

| Error Pattern | Likely Cause |
|--------------|--------------|
| `connection refused` | RDS not running or security group blocking |
| `timeout` | Network issue or RDS in wrong subnet |
| `password authentication failed` | Credential mismatch |
| `too many connections` | Connection pool exhaustion |

### Step 5: Verify Subnet Configuration

Ensure RDS is in the isolated database subnets (not public):

```bash
# Get RDS subnet group details
aws rds describe-db-subnet-groups \
  --db-subnet-group-name 3-tier-web-app-db-subnet-group \
  --query 'DBSubnetGroups[0].Subnets[*].[SubnetIdentifier,SubnetAvailabilityZone.Name]' \
  --output table

# Verify these match our database subnets
aws ec2 describe-subnets \
  --filters "Name=tag:Tier,Values=database" "Name=tag:Name,Values=*3-tier-web-app*" \
  --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock]' \
  --output table
```

---

## Recovery Actions

### Action 1: Start Stopped RDS Instance

```bash
aws rds start-db-instance \
  --db-instance-identifier 3-tier-web-app-db

# Monitor startup progress
watch -n 10 "aws rds describe-db-instances \
  --db-instance-identifier 3-tier-web-app-db \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text"
```

**Note:** RDS startup typically takes 3-5 minutes.

### Action 2: Add Missing Security Group Rule

If the app security group is not in the allowed inbound rules:

```bash
# Add inbound rule (temporary fix - should be done via Terraform)
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG \
  --protocol tcp \
  --port 5432 \
  --source-group $APP_SG

echo "Rule added. Update Terraform configuration to make permanent."
```

**Important:** After immediate fix, update `modules/security-groups/main.tf` to reflect the change and run `terraform apply` to make it permanent.

### Action 3: Restart Application Instances

If connectivity is restored but instances are stuck in unhealthy state:

```bash
# Trigger instance refresh on ASG
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name 3-tier-web-app-asg \
  --preferences '{"MinHealthyPercentage": 50, "InstanceWarmup": 300}'

# Monitor refresh status
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name 3-tier-web-app-asg \
  --query 'InstanceRefreshes[0].[Status,PercentageComplete]' \
  --output table
```

### Action 4: Connection Pool Exhaustion

If logs show `too many connections`:

```bash
# Check current connection count (requires psql access)
PGPASSWORD=$DB_PASSWORD psql -h $RDS_ENDPOINT -U admin -d webappdb -c \
  "SELECT count(*) as total_connections, 
          state, 
          usename 
   FROM pg_stat_activity 
   GROUP BY state, usename;"

# If needed, terminate idle connections
PGPASSWORD=$DB_PASSWORD psql -h $RDS_ENDPOINT -U admin -d webappdb -c \
  "SELECT pg_terminate_backend(pid) 
   FROM pg_stat_activity 
   WHERE state = 'idle' 
   AND query_start < now() - interval '10 minutes';"
```

---

## Verification

After applying fixes, verify the application is healthy:

```bash
# Check ALB target health
TG_ARN=$(aws elbv2 describe-target-groups \
  --names 3-tier-web-app-tg \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
  --output table

# Test application endpoint directly
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names 3-tier-web-app-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

curl -s -o /dev/null -w "%{http_code}" http://$ALB_DNS/health
# Expected: 200

# Verify CloudWatch alarm returns to OK
aws cloudwatch describe-alarms \
  --alarm-names 3-tier-web-app-alb-unhealthy-hosts \
  --query 'MetricAlarms[0].StateValue' \
  --output text
# Expected: OK
```

---

## Escalation

If the above steps don't resolve the issue:

1. **Check AWS Service Health Dashboard** for RDS issues in your region
2. **Open AWS Support case** with:
   - RDS instance identifier: `3-tier-web-app-db`
   - Error messages from CloudWatch Logs
   - Output from diagnostic commands above
3. **Notify on-call team** via PagerDuty

---

## Related Runbooks

- [ALB_5XX_ERRORS.md](./ALB_5XX_ERRORS.md) - Application-level errors
- [HIGH_CPU_UTILIZATION.md](./HIGH_CPU_UTILIZATION.md) - Performance issues
- [ASG_SCALING_ISSUES.md](./ASG_SCALING_ISSUES.md) - Capacity problems

---

## References

- [RDS Troubleshooting Guide](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Troubleshooting.html)
- [VPC Security Groups for RDS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Overview.RDSSecurityGroups.html)
- [Session Manager Setup](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)

