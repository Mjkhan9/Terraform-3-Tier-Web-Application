# Architecture Deep Dive

## System Architecture

This document provides a detailed explanation of the 3-tier web application architecture.

## Tier 1: Presentation Layer (Load Balancer)

### Application Load Balancer (ALB)

- **Type**: Application Load Balancer (Layer 7)
- **Subnets**: Public subnets across multiple AZs
- **Protocols**: HTTP (80), HTTPS (443) - optional
- **Features**:
  - Health checks on `/health` endpoint
  - Sticky sessions (session affinity)
  - Cross-zone load balancing
  - Access logging to S3
  - HTTP/2 enabled

### Security Group: ALB

- **Ingress**: HTTP (80) and HTTPS (443) from Internet (0.0.0.0/0)
- **Egress**: All traffic to application instances

## Tier 2: Application Layer (Compute)

### Auto Scaling Group

- **Instance Type**: t3.micro (Free Tier compatible)
- **Subnets**: Private subnets across multiple AZs
- **Scaling**:
  - Min: 2 instances
  - Max: 4 instances
  - Desired: 2 instances
- **Health Check**: ELB health check type
- **Launch Template**: Uses latest Amazon Linux 2 AMI

### EC2 Instances

Each instance runs:
- **OS**: Amazon Linux 2
- **Application**: Flask web application (Python 3)
- **Web Server**: Flask built-in server (port 80)
- **Monitoring**: CloudWatch agent
- **IAM Role**: Access to S3 and CloudWatch Logs

### Application Features

- **Web Interface**: Modern HTML/CSS/JavaScript UI
- **Database Integration**: PostgreSQL connection pooling
- **S3 Integration**: Asset storage and retrieval
- **Health Endpoint**: `/health` for load balancer checks
- **API Endpoints**: `/api/db-test`, `/api/s3-test`

### Security Group: Application

- **Ingress**:
  - HTTP (80) from ALB security group only
  - HTTPS (443) from ALB security group only
  - SSH (22) from VPC CIDR (for debugging)
- **Egress**: All outbound traffic (for updates, S3 access)

## Tier 3: Data Layer (Database)

### RDS PostgreSQL

- **Engine**: PostgreSQL 15.4
- **Instance Class**: db.t3.micro (Free Tier compatible)
- **Storage**: 20 GB GP2 (encrypted)
- **Subnets**: Private subnets (DB subnet group)
- **Backups**: 7-day retention, automated backups
- **Multi-AZ**: Disabled (enable for production)

### Security Group: RDS

- **Ingress**: PostgreSQL (5432) from application security group only
- **Egress**: All outbound traffic

## Networking Architecture

### VPC

- **CIDR**: 10.0.0.0/16
- **DNS**: Enabled (hostnames and support)
- **Flow Logs**: Enabled (CloudWatch Logs)

### Public Subnets

- **Purpose**: Internet-facing resources (ALB, NAT Gateways)
- **CIDR Blocks**: 10.0.0.0/24, 10.0.1.0/24 (one per AZ)
- **Route Table**: Routes to Internet Gateway
- **Resources**: ALB, NAT Gateways

### Private Subnets

- **Purpose**: Application and database resources
- **CIDR Blocks**: 10.0.10.0/24, 10.0.11.0/24 (one per AZ)
- **Route Table**: Routes to NAT Gateway (for internet access)
- **Resources**: EC2 instances, RDS database

### Internet Gateway

- **Purpose**: Provides internet access to public subnets
- **Attached to**: VPC

### NAT Gateways

- **Purpose**: Allows private subnet resources to access internet
- **Type**: One per AZ (for high availability)
- **Elastic IPs**: One per NAT Gateway
- **Cost**: ~$32/month per gateway

## Storage Architecture

### S3 Buckets

#### Application Assets Bucket

- **Purpose**: Store application assets (images, files, etc.)
- **Features**:
  - Versioning enabled
  - Server-side encryption (AES256)
  - Public access blocked
  - Lifecycle policies

#### ALB Logs Bucket

- **Purpose**: Store ALB access logs
- **Features**:
  - Public access blocked
  - Lifecycle policy (30-day retention)
  - Policy for ALB log delivery

## Security Architecture

### Network Security

1. **Security Groups**: Layer-based isolation
   - ALB: Internet-facing
   - Application: ALB-only access
   - RDS: Application-only access

2. **Network ACLs**: Default (allow all) - can be customized

3. **Private Subnets**: Application and database in private subnets

### Data Security

1. **Encryption at Rest**:
   - RDS: Storage encryption enabled
   - S3: Server-side encryption (AES256)

2. **Encryption in Transit**:
   - HTTPS support (optional, requires certificate)
   - RDS: SSL/TLS connections

3. **IAM Roles**: Least privilege access
   - EC2: S3 read/write, CloudWatch Logs
   - VPC Flow Logs: CloudWatch Logs write

### Access Control

- **SSH**: Restricted to VPC CIDR
- **Database**: Application security group only
- **S3**: IAM role-based access

## Monitoring Architecture

### CloudWatch Metrics

- **EC2**: CPU utilization, network I/O
- **ALB**: Request count, response time, error rates
- **RDS**: CPU, memory, storage, connections
- **Auto Scaling**: Group metrics

### CloudWatch Alarms

- **High CPU**: >80% for 2 periods (5 minutes each)
- **Low CPU**: <20% for 2 periods
- **ALB Response Time**: >2 seconds
- **Unhealthy Hosts**: >0 hosts
- **5xx Errors**: >10 errors in 5 minutes

### CloudWatch Logs

- **Application Logs**: `/aws/ec2/3-tier-web-app`
- **VPC Flow Logs**: `/aws/vpc/3-tier-web-app-flow-log`
- **RDS Logs**: PostgreSQL logs, upgrade logs

### SNS Notifications

- **Topic**: Alerts topic for all alarms
- **Subscriptions**: Email (optional, uncomment to enable)

## High Availability

### Multi-AZ Deployment

- **ALB**: Deployed across multiple AZs
- **EC2 Instances**: Distributed across AZs via Auto Scaling Group
- **RDS**: Single-AZ (can enable Multi-AZ for production)
- **NAT Gateways**: One per AZ for redundancy

### Auto Scaling

- **Scale Out**: Triggered by high CPU alarm
- **Scale In**: Triggered by low CPU alarm
- **Health Checks**: ELB health checks replace unhealthy instances
- **Cooldown**: 5 minutes between scaling actions

### Load Balancing

- **Algorithm**: Round-robin with sticky sessions
- **Health Checks**: HTTP GET to `/health` endpoint
- **Unhealthy Threshold**: 2 consecutive failures
- **Healthy Threshold**: 2 consecutive successes

## Disaster Recovery

### Backups

- **RDS**: Automated daily backups, 7-day retention
- **S3**: Versioning enabled
- **Terraform State**: Should be stored in S3 backend (commented out)

### Recovery Procedures

1. **Database**: Restore from automated backup
2. **Application**: Redeploy via Terraform
3. **Data**: Restore from S3 versioning

## Scalability

### Horizontal Scaling

- **Auto Scaling Group**: Automatically scales based on CPU
- **Load Balancer**: Distributes traffic across instances
- **Database**: Can be scaled vertically (instance class) or horizontally (read replicas)

### Vertical Scaling

- **EC2**: Change instance type in launch template
- **RDS**: Modify instance class (requires downtime)

## Cost Optimization

### Free Tier Usage

- **EC2**: t3.micro instances (750 hours/month)
- **RDS**: db.t3.micro instances (750 hours/month)
- **S3**: 5 GB storage
- **Data Transfer**: 1 GB/month

### Cost Reduction Strategies

1. **Single NAT Gateway**: Use one NAT Gateway instead of per-AZ
2. **Reserved Instances**: For predictable workloads
3. **Spot Instances**: For non-critical workloads
4. **S3 Lifecycle Policies**: Automatic log cleanup
5. **CloudWatch Log Retention**: 7-day retention

## Performance Optimization

### Application Layer

- **Connection Pooling**: Database connection reuse
- **Caching**: Can add Redis/ElastiCache
- **CDN**: Can add CloudFront for static assets

### Database Layer

- **Connection Pooling**: Managed by application
- **Read Replicas**: Can add for read scaling
- **Parameter Tuning**: Custom parameter group

### Network Layer

- **ALB**: HTTP/2 enabled
- **Cross-Zone Load Balancing**: Enabled
- **Sticky Sessions**: Enabled for session persistence

## Future Enhancements

### Recommended Additions

1. **AWS WAF**: Web application firewall
2. **CloudFront**: CDN for static assets
3. **Route 53**: Custom domain and DNS
4. **ACM**: SSL/TLS certificates
5. **Secrets Manager**: Database credentials
6. **ElastiCache**: Redis for caching
7. **SQS/SNS**: Message queue for async processing
8. **Lambda**: Serverless functions
9. **API Gateway**: RESTful API management
10. **CodePipeline**: CI/CD pipeline

---

This architecture demonstrates production-ready cloud infrastructure with best practices for security, scalability, and cost optimization.

