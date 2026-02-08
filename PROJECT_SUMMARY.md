# Project Summary: Terraform 3-Tier Web Application

## Overview

Auto-scaling web application infrastructure deployed on AWS using Terraform. The project demonstrates a production-ready architecture pattern with proper network isolation, security, and monitoring.

## What's Implemented

**Core Infrastructure**
- VPC with public/private subnets (multi-AZ)
- Application Load Balancer with health checks
- Auto Scaling Group with EC2 instances
- RDS PostgreSQL database
- S3 buckets for assets and logs
- Security Groups with proper isolation
- Written entirely in Terraform

## Architecture

### Modular Design
7 Terraform modules for clean separation:
- vpc
- security-groups
- s3
- rds
- alb
- asg
- cloudwatch

### Network Layout
- Multi-AZ deployment for high availability
- Public subnets for ALB and NAT
- Private subnets for application and database
- VPC Flow Logs for network monitoring

### Application Stack
- Flask web application with modern UI
- PostgreSQL database with connection pooling
- S3 integration for asset storage
- CloudWatch logging

### Security
- Network isolation via security groups
- Encrypted storage (RDS and S3)
- IAM roles with least privilege
- Private subnets for app and database tiers

## Project Structure

```
Terraform-3-Tier-Web-Application/
├── main.tf                    # Main configuration
├── variables.tf               # Variable definitions
├── outputs.tf                 # Output definitions
├── versions.tf                # Provider requirements
├── terraform.tfvars.example   # Example variables
├── deploy.sh                  # Deployment script
├── README.md                  # Main documentation
├── ARCHITECTURE.md            # Architecture deep dive
├── DEPLOYMENT.md              # Deployment guide
│
└── modules/
    ├── vpc/                   # VPC, subnets, NAT, IGW
    ├── security-groups/       # Security group rules
    ├── s3/                    # S3 buckets and policies
    ├── rds/                   # RDS PostgreSQL database
    ├── alb/                   # Application Load Balancer
    ├── asg/                   # Auto Scaling Group
    └── cloudwatch/            # CloudWatch alarms
```

## AWS Resources Created

- 1 VPC with 2 public and 2 private subnets
- 1 Internet Gateway
- 2 NAT Gateways (one per AZ)
- 1 Application Load Balancer
- 1 Target Group
- 1 Auto Scaling Group (2-4 instances)
- 1 RDS PostgreSQL instance
- 2 S3 Buckets (assets + logs)
- 3 Security Groups (ALB, App, RDS)
- 5 CloudWatch Alarms
- 1 SNS Topic
- Multiple IAM Roles and policies

## Cost Estimate

### Free Tier (First 12 Months)
- EC2: 750 hours/month free (t3.micro)
- RDS: 750 hours/month free (db.t3.micro)
- S3: 5 GB storage free

### After Free Tier
- NAT Gateways: ~$64/month (2 gateways)
- ALB: ~$16/month + data transfer
- EC2: ~$15/month (2 instances)
- RDS: ~$15/month
- Total: ~$110-150/month

Use single NAT Gateway to save ~$32/month in dev environments.

## Quick Start

1. Clone repository
2. Configure variables: `cp terraform.tfvars.example terraform.tfvars`
3. Set database password in `terraform.tfvars`
4. Deploy: `terraform init && terraform apply`
5. Access: Get URL from `terraform output application_url`

See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed instructions.

## Documentation

- [README.md](README.md) - Main documentation with architecture diagram
- [ARCHITECTURE.md](ARCHITECTURE.md) - Deep dive into architecture
- [DEPLOYMENT.md](DEPLOYMENT.md) - Step-by-step deployment guide

---

**Status**: Complete and ready for deployment
