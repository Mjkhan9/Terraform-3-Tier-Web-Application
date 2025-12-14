# 🚀 Terraform 3-Tier Web Application

A production-grade, auto-scaling web application infrastructure deployed on AWS using Terraform. This project demonstrates enterprise-level cloud architecture with Infrastructure as Code (IaC) best practices.

## 📋 Table of Contents

- [Architecture](#architecture)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Project Structure](#project-structure)
- [Configuration](#configuration)
- [Deployment](#deployment)
- [Accessing the Application](#accessing-the-application)
- [Monitoring](#monitoring)
- [Cost Optimization](#cost-optimization)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                 │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
                  ┌────────────────┐
                  │   Route 53      │  (Optional DNS)
                  └────────┬────────┘
                           │
                           ▼
            ┌──────────────────────────────┐
            │  Application Load Balancer   │
            │    (Public Subnets)          │
            │  - HTTP (Port 80)            │
            │  - HTTPS (Port 443)           │
            └──────────────┬───────────────┘
                           │
                           ▼
        ┌──────────────────────────────────────┐
        │      Security Group (ALB)            │
        │  - Allow HTTP/HTTPS from Internet    │
        └──────────────────┬───────────────────┘
                           │
                           ▼
        ┌──────────────────────────────────────┐
        │    Auto Scaling Group (Multi-AZ)     │
        │  ┌────────────┐    ┌────────────┐    │
        │  │ EC2 (AZ-1) │    │ EC2 (AZ-2) │    │
        │  │ Flask App  │    │ Flask App  │    │
        │  │ Port 80    │    │ Port 80    │    │
        │  └─────┬──────┘    └─────┬──────┘    │
        └────────┼─────────────────┼───────────┘
                 │                 │
                 ▼                 ▼
        ┌──────────────────────────────────────┐
        │   Security Group (Application)       │
        │  - Allow HTTP from ALB only           │
        │  - Allow SSH from VPC                 │
        └──────────────────┬───────────────────┘
                           │
                           ▼
        ┌──────────────────────────────────────┐
        │         RDS PostgreSQL                │
        │    (Private Subnets, Multi-AZ)        │
        │  - db.t3.micro (Free Tier)            │
        │  - Encrypted Storage                  │
        │  - Automated Backups                  │
        └──────────────────────────────────────┘
                           │
        ┌──────────────────┴───────────────────┐
        │   Security Group (RDS)               │
        │  - Allow PostgreSQL from App SG only  │
        └──────────────────────────────────────┘

        ┌──────────────────────────────────────┐
        │         S3 Buckets                   │
        │  - Application Assets                │
        │  - ALB Access Logs                   │
        │  - Versioning Enabled                │
        │  - Encryption Enabled                │
        └──────────────────────────────────────┘

        ┌──────────────────────────────────────┐
        │      CloudWatch Monitoring            │
        │  - CPU Utilization Alarms            │
        │  - ALB Response Time Alarms           │
        │  - Unhealthy Host Alarms              │
        │  - 5xx Error Alarms                   │
        │  - VPC Flow Logs                      │
        └──────────────────────────────────────┘
```

### Network Architecture

```
VPC (10.0.0.0/16)
│
├── Public Subnets (Multi-AZ)
│   ├── 10.0.0.0/24 (AZ-1) → Internet Gateway
│   └── 10.0.1.0/24 (AZ-2) → Internet Gateway
│       └── Application Load Balancer
│       └── NAT Gateways
│
└── Private Subnets (Multi-AZ)
    ├── 10.0.10.0/24 (AZ-1) → NAT Gateway
    └── 10.0.11.0/24 (AZ-2) → NAT Gateway
        └── EC2 Instances (Auto Scaling Group)
        └── RDS PostgreSQL Database
```

## ✨ Features

### Core Infrastructure
- ✅ **VPC** with public/private subnets across multiple Availability Zones
- ✅ **Application Load Balancer** with health checks and sticky sessions
- ✅ **Auto Scaling Group** with launch templates and user data scripts
- ✅ **RDS PostgreSQL** database with automated backups
- ✅ **S3 Buckets** for assets and ALB access logs
- ✅ **Security Groups** with proper network isolation
- ✅ **NAT Gateways** for private subnet internet access
- ✅ **VPC Flow Logs** for network monitoring

### Application Features
- ✅ **Flask Web Application** with modern UI
- ✅ **Database Connectivity** with connection pooling
- ✅ **S3 Integration** for asset storage
- ✅ **Health Check Endpoint** (`/health`)
- ✅ **API Endpoints** for database and S3 testing
- ✅ **CloudWatch Logs** integration

### Monitoring & Observability
- ✅ **CloudWatch Alarms** for CPU, response time, and errors
- ✅ **SNS Topic** for alert notifications
- ✅ **ALB Access Logs** stored in S3
- ✅ **VPC Flow Logs** for network analysis
- ✅ **Application Logs** in CloudWatch Logs

### Security
- ✅ **Network Isolation** with security groups
- ✅ **Encrypted RDS** storage
- ✅ **Encrypted S3** buckets
- ✅ **Private Subnets** for application and database tiers
- ✅ **IAM Roles** with least privilege access
- ✅ **Security Group** rules restricting access

### Cost Optimization
- ✅ **Free Tier Compatible** (t3.micro, db.t3.micro)
- ✅ **S3 Lifecycle Policies** for log retention
- ✅ **CloudWatch Log Retention** (7 days)
- ✅ **Single NAT Gateway** option (configurable)

## 📦 Prerequisites

- **AWS Account** with appropriate permissions
- **Terraform** >= 1.0 installed
- **AWS CLI** configured (optional, for CloudShell)
- **Git** (for cloning the repository)

### AWS Permissions Required

The AWS credentials used must have permissions to create:
- VPC, Subnets, Internet Gateway, NAT Gateway
- EC2 Instances, Launch Templates, Auto Scaling Groups
- Application Load Balancer, Target Groups
- RDS Instances, DB Subnet Groups
- S3 Buckets
- Security Groups
- IAM Roles and Policies
- CloudWatch Logs, Alarms, SNS Topics

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone <repository-url>
cd Terraform-3-Tier-Web-Application
```

### 2. Configure Variables

Copy the example variables file and customize:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set your database password:

```hcl
aws_region = "us-east-1"
project_name = "3-tier-web-app"
environment = "dev"

# REQUIRED: Set your database credentials
db_username = "admin"
db_password = "YourSecurePassword123!"  # Change this!

# Optional: ACM certificate ARN for HTTPS
# certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc123"
```

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Review the Plan

```bash
terraform plan
```

### 5. Deploy Infrastructure

```bash
terraform apply
```

Type `yes` when prompted to confirm the deployment.

### 6. Get Application URL

After deployment completes, get the ALB DNS name:

```bash
terraform output application_url
```

Or view all outputs:

```bash
terraform output
```

## 📁 Project Structure

```
.
├── main.tf                    # Main Terraform configuration
├── variables.tf               # Variable definitions
├── outputs.tf                # Output definitions
├── terraform.tfvars.example  # Example variables file
├── .gitignore                # Git ignore file
├── README.md                 # This file
│
└── modules/
    ├── vpc/                  # VPC Module
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── security-groups/      # Security Groups Module
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── s3/                   # S3 Module
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── rds/                  # RDS Module
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── alb/                  # Application Load Balancer Module
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── asg/                  # Auto Scaling Group Module
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── user_data.sh      # EC2 user data script
    │
    └── cloudwatch/           # CloudWatch Module
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

## ⚙️ Configuration

### Key Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region for resources | `us-east-1` |
| `project_name` | Name of the project | `3-tier-web-app` |
| `environment` | Environment name | `dev` |
| `vpc_cidr` | CIDR block for VPC | `10.0.0.0/16` |
| `instance_type` | EC2 instance type | `t3.micro` |
| `asg_min_size` | Minimum ASG instances | `2` |
| `asg_max_size` | Maximum ASG instances | `4` |
| `asg_desired_capacity` | Desired ASG instances | `2` |
| `db_instance_class` | RDS instance class | `db.t3.micro` |
| `db_allocated_storage` | RDS storage (GB) | `20` |
| `db_name` | Database name | `webappdb` |
| `db_username` | Database username | `admin` |
| `db_password` | Database password | **Required** |

### Customization Examples

#### Single NAT Gateway (Cost Savings)

Edit `modules/vpc/main.tf` to use a single NAT Gateway:

```hcl
resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway ? 1 : 0  # Change from length(...)
  # ... rest of configuration
}
```

#### Enable HTTPS

1. Request an ACM certificate in your region
2. Add the certificate ARN to `terraform.tfvars`:

```hcl
certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc123"
```

#### Adjust Auto Scaling

Modify `terraform.tfvars`:

```hcl
asg_min_size         = 1
asg_max_size         = 10
asg_desired_capacity  = 2
```

## 🌐 Accessing the Application

### Web Interface

After deployment, access the application at:

```
http://<alb-dns-name>
```

The ALB DNS name is displayed in the Terraform outputs.

### Health Check Endpoint

```bash
curl http://<alb-dns-name>/health
```

### API Endpoints

- **Database Test**: `GET /api/db-test`
- **S3 Test**: `GET /api/s3-test`

## 📊 Monitoring

### CloudWatch Alarms

The following alarms are created:

- **High CPU Utilization** (>80%)
- **Low CPU Utilization** (<20%)
- **ALB High Response Time** (>2 seconds)
- **ALB Unhealthy Hosts** (>0)
- **ALB 5xx Errors** (>10 in 5 minutes)

### Viewing Logs

#### Application Logs

```bash
aws logs tail /aws/ec2/3-tier-web-app --follow
```

#### ALB Access Logs

ALB access logs are stored in S3:
```
s3://<project-name>-alb-logs-<environment>-<suffix>/alb/
```

#### VPC Flow Logs

```bash
aws logs tail /aws/vpc/3-tier-web-app-flow-log --follow
```

### SNS Alerts

To receive email alerts, uncomment and configure the SNS subscription in `modules/cloudwatch/main.tf`:

```hcl
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "your-email@example.com"
}
```

Then run `terraform apply` again.

## 💰 Cost Optimization

### Free Tier Eligibility

This infrastructure is designed to stay within AWS Free Tier limits:

- **EC2**: t3.micro instances (750 hours/month free)
- **RDS**: db.t3.micro instances (750 hours/month free)
- **S3**: 5 GB storage free
- **Data Transfer**: 1 GB/month free

### Estimated Monthly Cost (Outside Free Tier)

- **NAT Gateway**: ~$32/month per gateway
- **ALB**: ~$16/month + data transfer
- **EC2**: ~$7.50/month per t3.micro instance
- **RDS**: ~$15/month for db.t3.micro
- **S3**: ~$0.023/GB/month

**Total**: ~$100-150/month for 2 instances (depending on usage)

### Cost Reduction Tips

1. **Use Single NAT Gateway**: Modify VPC module to use one NAT Gateway
2. **Reduce Instance Count**: Set `asg_desired_capacity = 1` for dev
3. **Delete When Not in Use**: Use `terraform destroy` when not testing
4. **Use Spot Instances**: Modify launch template for spot pricing
5. **S3 Lifecycle Policies**: Already configured for log cleanup

## 🔧 Troubleshooting

### Application Not Responding

1. **Check ALB Health Checks**:
   ```bash
   aws elbv2 describe-target-health --target-group-arn <target-group-arn>
   ```

2. **Check EC2 Instance Status**:
   ```bash
   aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names <asg-name>
   ```

3. **View Application Logs**:
   ```bash
   aws logs tail /aws/ec2/3-tier-web-app --follow
   ```

### Database Connection Issues

1. **Verify Security Groups**: Ensure RDS security group allows PostgreSQL from app security group
2. **Check RDS Status**:
   ```bash
   aws rds describe-db-instances --db-instance-identifier <db-id>
   ```
3. **Test Connection**: Use the `/api/db-test` endpoint

### High Costs

1. **Check NAT Gateway Usage**: NAT Gateways are the most expensive component
2. **Review CloudWatch Logs**: Large log volumes can add up
3. **Monitor S3 Storage**: Check bucket sizes
4. **Review ALB Data Transfer**: High traffic increases costs

## 🧹 Cleanup

To destroy all resources and avoid charges:

```bash
terraform destroy
```

**Note**: This will delete all resources including:
- VPC and networking components
- EC2 instances and Auto Scaling Groups
- RDS database (with final snapshot disabled)
- S3 buckets (if empty)
- Load Balancers
- All associated resources

### Manual Cleanup Required

Some resources may require manual cleanup:

1. **S3 Buckets**: If they contain objects, delete manually
2. **CloudWatch Logs**: May require manual deletion
3. **NAT Gateway Elastic IPs**: Released automatically, but verify

## 📝 Notes

### Database Password

**Important**: The database password is stored in Terraform state. For production:

1. Use AWS Secrets Manager
2. Use Terraform Cloud/Enterprise for state encryption
3. Rotate passwords regularly

### Production Considerations

For production deployments, consider:

1. **Multi-AZ RDS**: Enable `multi_az = true` in RDS module
2. **WAF**: Add AWS WAF for DDoS protection
3. **CloudFront**: Add CDN for static assets
4. **Route 53**: Configure custom domain
5. **Backup Strategy**: Enhanced automated backups
6. **Monitoring**: Enhanced CloudWatch dashboards
7. **Security**: AWS GuardDuty, Security Hub
8. **Compliance**: Enable AWS Config

## 🤝 Contributing

This is a portfolio project demonstrating cloud engineering skills. Feel free to fork and customize for your own use.

## 📄 License

This project is provided as-is for educational and portfolio purposes.

## 👤 Author

Built as a demonstration of cloud engineering capabilities with Infrastructure as Code.

---

**Built with ❤️ using Terraform and AWS**

