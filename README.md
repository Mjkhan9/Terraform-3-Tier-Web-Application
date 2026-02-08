# Terraform 3-Tier Web Application

Auto-scaling web application infrastructure on AWS, deployed entirely with Terraform.

I built this project to demonstrate a production-ready architecture pattern - the kind of setup you'd actually use for a real application. It includes proper network isolation, database encryption, comprehensive monitoring, and stays within Free Tier limits for testing.

---

## Architecture

```
VPC (10.0.0.0/16)
├── Public Subnets (Multi-AZ)
│   ├── ALB (Port 80/443)
│   └── NAT Gateways
├── Private Subnets (Multi-AZ)
│   ├── EC2 (Auto Scaling Group)
│   └── RDS (PostgreSQL)
└── Security Groups (Chained)
    └── Internet → ALB → App → DB
```

Traffic flows through an Application Load Balancer to EC2 instances running Flask, which connect to a PostgreSQL database in isolated private subnets. The database has no internet access - all traffic goes through the NAT Gateway.

### Security Group Flow

```
Internet ──[80/443]──▶ ALB-SG ──[80]──▶ App-SG ──[5432]──▶ RDS-SG
```

No skip-level access. Each tier only accepts connections from the tier above it.

---

## What's Included

**Core Infrastructure**
- VPC with public/private subnets across multiple Availability Zones
- Application Load Balancer with health checks and sticky sessions
- Auto Scaling Group with launch templates and user data scripts
- RDS PostgreSQL with automated backups and encryption
- S3 buckets for assets and ALB access logs
- NAT Gateways for private subnet internet access
- VPC Flow Logs for network monitoring

**Application**
- Flask web app with database connectivity
- Health check endpoint (`/health`)
- API endpoints for testing DB and S3 connections
- CloudWatch Logs integration

**Monitoring & Observability**
- CloudWatch Alarms for CPU, response time, errors
- CloudWatch Dashboard for centralized operations view
- Custom log metric filters for application errors
- SNS Topic for alert notifications
- ALB Access Logs in S3
- VPC Flow Logs for network analysis

**Security & Compliance**
- Network isolation with security groups
- Encrypted RDS storage
- Encrypted S3 buckets
- IAM roles with least privilege access
- Private subnets for application and database tiers
- AWS Config rules for continuous compliance monitoring

**Operations**
- Operational runbooks for common issues (RDS, ALB, ASG, CPU)
- Drift detection script for configuration validation
- Cost analysis script for budget tracking
- GitHub Actions CI/CD with automated security scanning (tfsec, Checkov)

---

## Prerequisites

- AWS Account with permissions for VPC, EC2, RDS, ALB, S3, IAM, CloudWatch
- Terraform >= 1.0
- AWS CLI configured (optional)

---

## Quick Start

### 1. Clone and Configure

```bash
git clone <repository-url>
cd Terraform-3-Tier-Web-Application
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region   = "us-east-1"
project_name = "3-tier-web-app"
environment  = "dev"

# Set your database credentials
db_username = "admin"
db_password = "YourSecurePassword123!"
```

### 2. Deploy

```bash
terraform init
terraform plan
terraform apply
```

### 3. Access the Application

```bash
terraform output application_url
```

---

## Project Structure

```
.
├── main.tf                    # Main configuration
├── variables.tf               # Variable definitions
├── outputs.tf                 # Output definitions
├── terraform.tfvars.example   # Example variables
├── DEPLOYMENT_EVIDENCE.md     # Validation evidence and plan output
├── DESIGN_DECISIONS.md        # Architecture rationale
├── modules/
│   ├── vpc/                   # VPC, subnets, gateways
│   ├── vpc-endpoints/         # VPC Endpoints for AWS services
│   ├── security-groups/       # Security group rules
│   ├── s3/                    # S3 buckets
│   ├── rds/                   # PostgreSQL database
│   ├── alb/                   # Application Load Balancer
│   ├── asg/                   # Auto Scaling Group
│   ├── cloudwatch/            # Monitoring, alarms, and dashboard
│   ├── aws-config/            # AWS Config rules for compliance
│   ├── secrets/               # Secrets Manager configuration
│   └── github-oidc/           # GitHub Actions OIDC authentication
├── runbooks/                  # Operational troubleshooting guides
│   ├── RDS_CONNECTION_FAILURE.md
│   ├── HIGH_CPU_UTILIZATION.md
│   ├── ALB_5XX_ERRORS.md
│   ├── ASG_SCALING_ISSUES.md
│   └── SECRETS_ROTATION.md
└── scripts/
    ├── drift-detection.sh     # Terraform drift detection
    ├── cost-analysis.sh       # AWS cost analysis
    └── bootstrap-backend.sh   # Backend setup script
```

---

## Configuration

Key variables you can customize:

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region | `us-east-1` |
| `vpc_cidr` | VPC CIDR block | `10.0.0.0/16` |
| `instance_type` | EC2 instance type | `t3.micro` |
| `asg_min_size` | Minimum instances | `2` |
| `asg_max_size` | Maximum instances | `4` |
| `db_instance_class` | RDS instance class | `db.t3.micro` |

### Enable HTTPS

1. Request an ACM certificate
2. Add to `terraform.tfvars`:

```hcl
certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc123"
```

---

## Monitoring

### CloudWatch Alarms

The deployment creates alarms for:
- High CPU utilization (>80%)
- Low CPU utilization (<20%)
- ALB response time (>2 seconds)
- Unhealthy hosts
- 5xx errors

### Viewing Logs

```bash
# Application logs
aws logs tail /aws/ec2/3-tier-web-app --follow

# VPC Flow Logs
aws logs tail /aws/vpc/3-tier-web-app-flow-log --follow
```

### API Endpoints

- Health check: `GET /health`
- Database test: `GET /api/db-test`
- S3 test: `GET /api/s3-test`

---

## Cost

Designed for AWS Free Tier:
- EC2: t3.micro (750 hours/month free)
- RDS: db.t3.micro (750 hours/month free)
- S3: 5 GB storage free

**Outside Free Tier (estimate):**

| Service | Monthly Cost |
|---------|--------------|
| NAT Gateways (2x) | ~$65 |
| ALB | ~$20 |
| EC2 t3.micro (2x) | ~$15 |
| RDS db.t3.micro | ~$15 |
| VPC Endpoints (3x) | ~$22 |
| S3 + misc | ~$5 |
| **Total** | **~$140/month** |

### Cost Analysis

Run the cost analysis script to get a detailed breakdown:

```bash
./scripts/cost-analysis.sh --detailed
```

### Cost Reduction Tips

1. Disable NAT Gateways (`enable_nat_gateway = false`) - saves ~$65/month
2. Set `asg_desired_capacity = 1` when not testing
3. Run `terraform destroy` when done
4. Consider spot instances for non-production
5. Use reserved instances for long-term production workloads

---

## Troubleshooting

For detailed troubleshooting procedures, see the [runbooks](./runbooks/) directory.

### Quick Diagnostic Commands

```bash
# Check ALB health
aws elbv2 describe-target-health --target-group-arn <arn>

# Check ASG status
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names 3-tier-web-app-asg

# View application logs
aws logs tail /aws/ec2/3-tier-web-app --follow

# Check for infrastructure drift
./scripts/drift-detection.sh
```

### Runbooks Available

| Issue | Runbook |
|-------|---------|
| RDS connection failures | [RDS_CONNECTION_FAILURE.md](./runbooks/RDS_CONNECTION_FAILURE.md) |
| HTTP 5XX errors | [ALB_5XX_ERRORS.md](./runbooks/ALB_5XX_ERRORS.md) |
| High CPU utilization | [HIGH_CPU_UTILIZATION.md](./runbooks/HIGH_CPU_UTILIZATION.md) |
| ASG scaling issues | [ASG_SCALING_ISSUES.md](./runbooks/ASG_SCALING_ISSUES.md) |
| Credential rotation | [SECRETS_ROTATION.md](./runbooks/SECRETS_ROTATION.md) |

### Database Connection Issues

1. Verify RDS security group allows PostgreSQL from app security group
2. Check RDS status: `aws rds describe-db-instances`
3. Test connection via `/api/db-test` endpoint

---

## Cleanup

```bash
terraform destroy
```

This removes all resources. Note that S3 buckets with objects may require manual deletion.

---

## Production Considerations

For actual production use, you'd want to add:
- Multi-AZ RDS (`multi_az = true`)
- AWS WAF for DDoS protection
- CloudFront CDN
- Route 53 for custom domain
- AWS GuardDuty and Security Hub
- Secrets Manager for database credentials

---

## Author

**Mohammad Khan**  
AWS Solutions Architect Associate

[LinkedIn](https://linkedin.com/in/mohammad-jkhan) · [GitHub](https://github.com/Mjkhan9)

---

## License

Provided for educational and portfolio purposes.
