# Operational Runbooks

This directory contains operational runbooks for the 3-Tier Web Application infrastructure. These runbooks provide step-by-step procedures for diagnosing and resolving common issues.

---

## Quick Reference

| Issue | Runbook | Severity |
|-------|---------|----------|
| Database connection errors | [RDS_CONNECTION_FAILURE.md](./RDS_CONNECTION_FAILURE.md) | P1 Critical |
| HTTP 5XX errors | [ALB_5XX_ERRORS.md](./ALB_5XX_ERRORS.md) | P1 Critical |
| High CPU on EC2 instances | [HIGH_CPU_UTILIZATION.md](./HIGH_CPU_UTILIZATION.md) | P2 High |
| ASG not scaling | [ASG_SCALING_ISSUES.md](./ASG_SCALING_ISSUES.md) | P2 High |
| Credential rotation | [SECRETS_ROTATION.md](./SECRETS_ROTATION.md) | P3 Medium |

---

## Runbook Standards

All runbooks follow a consistent format:

1. **Overview** - What the runbook covers
2. **Symptoms** - How to identify the issue
3. **Diagnostic Steps** - AWS CLI commands to investigate
4. **Recovery Actions** - How to fix the issue
5. **Verification** - Confirm the fix worked
6. **Related Runbooks** - Cross-references
7. **References** - AWS documentation links

---

## Prerequisites

### Required Tools

```bash
# AWS CLI v2
aws --version  # Should be 2.x

# jq for JSON parsing
jq --version

# Session Manager plugin (for SSM access)
session-manager-plugin --version
```

### IAM Permissions

The on-call engineer needs these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "rds:Describe*",
        "elbv2:Describe*",
        "autoscaling:Describe*",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "autoscaling:StartInstanceRefresh",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:DescribeAlarms",
        "logs:FilterLogEvents",
        "ssm:StartSession",
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "*"
    }
  ]
}
```

### Environment Setup

```bash
# Configure AWS CLI profile
export AWS_PROFILE=production
export AWS_REGION=us-east-1

# Verify access
aws sts get-caller-identity
```

---

## Common Patterns

### Getting Resource Identifiers

```bash
# All commands use consistent naming:
# - ASG: 3-tier-web-app-asg
# - ALB: 3-tier-web-app-alb
# - Target Group: 3-tier-web-app-tg
# - RDS: 3-tier-web-app-db
# - Log Group: /aws/ec2/3-tier-web-app
```

### Quick Health Check

```bash
# One-liner to check overall system health
echo "=== ALB ===" && \
aws elbv2 describe-load-balancers --names 3-tier-web-app-alb \
  --query 'LoadBalancers[0].State.Code' && \
echo "=== Targets ===" && \
aws elbv2 describe-target-health --target-group-arn $(aws elbv2 describe-target-groups \
  --names 3-tier-web-app-tg --query 'TargetGroups[0].TargetGroupArn' --output text) \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]' --output table && \
echo "=== RDS ===" && \
aws rds describe-db-instances --db-instance-identifier 3-tier-web-app-db \
  --query 'DBInstances[0].DBInstanceStatus' && \
echo "=== Alarms ===" && \
aws cloudwatch describe-alarms --alarm-name-prefix 3-tier-web-app \
  --query 'MetricAlarms[?StateValue!=`OK`].[AlarmName,StateValue]' --output table
```

---

## Escalation Path

1. **L1 - On-Call Engineer**: Follow runbook procedures
2. **L2 - Platform Team Lead**: Complex issues requiring code changes
3. **L3 - AWS Support**: Infrastructure-level issues
4. **Emergency**: Page all engineers via PagerDuty

---

## Contributing

When adding new runbooks:

1. Use the standard template format
2. Include real AWS CLI commands (tested)
3. Add to this README's quick reference table
4. Cross-reference related runbooks
5. Test all commands before merging

