# Design Decisions

This document explains the architectural and implementation decisions made in this project, demonstrating understanding of AWS best practices and trade-offs.

## Table of Contents

1. [Network Architecture](#network-architecture)
2. [Security Model](#security-model)
3. [State Management](#state-management)
4. [Compute Strategy](#compute-strategy)
5. [Database Design](#database-design)
6. [CI/CD Pipeline](#cicd-pipeline)
7. [Cost Optimization](#cost-optimization)

---

## Network Architecture

### Decision: Three-Tier Subnet Isolation

**Choice**: Separate Public, Private (Application), and Isolated (Database) subnets.

**Why**:
```
Public Subnets     → ALB, NAT Gateways (internet-facing)
Private Subnets    → EC2 instances (outbound internet via NAT)
Isolated Subnets   → RDS database (NO internet access)
```

**Rationale**:
- **Compliance**: Satisfies PCI-DSS and HIPAA requirements for data isolation
- **Defense in Depth**: Even if application layer is compromised, database cannot exfiltrate data to internet
- **Least Privilege**: Database only needs to communicate with application tier

**Alternative Considered**: Single private subnet for both app and database
- ❌ Rejected: Violates network segmentation best practices

### Decision: VPC Endpoints Instead of NAT for AWS Services

**Choice**: Use VPC Endpoints (PrivateLink) for S3, CloudWatch, Secrets Manager, and SSM.

**Why**:
- Traffic stays on AWS backbone network (never touches internet)
- Reduced NAT Gateway data processing costs (~$0.045/GB saved)
- Lower latency for AWS API calls
- Required for isolated database subnets to access AWS services

**Cost Impact**:
- Gateway Endpoints (S3, DynamoDB): **FREE**
- Interface Endpoints: ~$7.20/month each, but saves NAT costs

### Decision: Dynamic Availability Zone Selection

**Choice**: Use `data "aws_availability_zones"` instead of hardcoding AZs.

```hcl
data "aws_availability_zones" "available" {
  state = "available"
}
```

**Why**:
- Portability across AWS accounts (AZ mapping varies)
- Automatically adapts to regions with different AZ counts
- Handles AZ deprecation gracefully

---

## Security Model

### Decision: Security Group Chaining (Not CIDR-Based)

**Choice**: Reference Security Group IDs instead of CIDR blocks for internal traffic.

```hcl
# ✅ CORRECT: Security Group Reference
ingress {
  from_port       = 5432
  security_groups = [aws_security_group.app.id]
}

# ❌ AVOID: CIDR-based rules for internal traffic
ingress {
  from_port   = 5432
  cidr_blocks = ["10.0.0.0/16"]
}
```

**Why**:
- More restrictive: Only tagged resources can communicate
- Self-documenting: Shows intended traffic flow
- Dynamic: Works even if subnets change
- Audit-friendly: Clear dependency chain

### Decision: IAM Instance Profiles (Not Access Keys)

**Choice**: EC2 instances use IAM Roles via Instance Profiles.

**Why**:
- No long-lived credentials to rotate or leak
- Automatic credential rotation by AWS
- CloudTrail audit trail for all API calls
- Supports fine-grained resource-level permissions

**Anti-Pattern Avoided**: Embedding AWS_ACCESS_KEY_ID in application code or environment variables.

### Decision: AWS Secrets Manager for Database Credentials

**Choice**: Store database password in Secrets Manager, not terraform.tfvars.

**Why**:
- Removes secrets from Terraform state file
- Enables automatic rotation without redeployment
- Provides audit trail of secret access
- Supports compliance requirements (SOC2, HIPAA)

**Trade-off**: Adds ~$0.40/month cost + $0.05 per 10,000 API calls

---

## State Management

### Decision: S3 + DynamoDB Remote Backend

**Choice**: Store Terraform state in S3 with DynamoDB locking.

```hcl
backend "s3" {
  bucket         = "terraform-state-..."
  key            = "3-tier-web-app/terraform.tfstate"
  encrypt        = true
  dynamodb_table = "terraform-state-lock"
}
```

**Why**:
- **Team Collaboration**: Single source of truth
- **State Locking**: Prevents concurrent modifications (race conditions)
- **Versioning**: Recovery from state corruption
- **Encryption**: Protects sensitive data in state file
- **CI/CD Ready**: Accessible from GitHub Actions

**Alternative Considered**: Terraform Cloud
- Viable but adds vendor dependency
- S3 approach is more portable and educational

### Decision: Separate Bootstrap Process for Backend

**Choice**: Create backend resources via shell script before Terraform.

**Why**:
- Chicken-and-egg problem: Can't use Terraform to create its own backend
- One-time setup, then infrastructure is self-managing
- Documents the complete setup process

---

## Compute Strategy

### Decision: Launch Templates (Not Launch Configurations)

**Choice**: Use `aws_launch_template` instead of deprecated `aws_launch_configuration`.

**Why**:
- Supports versioning (rollback capability)
- Latest instance types and features
- Mixed instance policies
- Better parameter organization

### Decision: Auto Scaling Group with ELB Health Checks

**Choice**: `health_check_type = "ELB"` instead of "EC2".

**Why**:
- EC2 health check only detects hardware failures
- ELB health check detects application failures
- Creates self-healing system: unhealthy instances replaced automatically

### Decision: Deep Health Check Endpoint

**Choice**: `/health` endpoint that tests database connectivity.

```python
@app.route('/health')
def health():
    # Test database connection
    conn = get_db_connection()
    if conn:
        return jsonify({'status': 'healthy'}), 200
    return jsonify({'status': 'unhealthy'}), 500
```

**Why**:
- Detects database connectivity issues
- ALB stops routing to instances that can't serve requests
- Enables automatic failover during partial outages

---

## Database Design

### Decision: PostgreSQL on RDS (Not Self-Managed)

**Choice**: Amazon RDS PostgreSQL instead of EC2-hosted database.

**Why**:
- Automated backups and point-in-time recovery
- Multi-AZ failover (single setting)
- Automatic patching and maintenance
- Performance Insights included

**Trade-off**: Slightly higher cost than EC2, but operational overhead is dramatically reduced.

### Decision: Encryption at Rest with AWS-Managed Keys

**Choice**: `storage_encrypted = true` with default KMS key.

**Why**:
- Compliance requirement for most frameworks
- No performance impact with modern instance types
- AWS-managed key reduces operational burden

**Future Enhancement**: Customer-managed KMS key for full key rotation control.

---

## CI/CD Pipeline

### Decision: GitHub Actions with OIDC Authentication

**Choice**: Use OIDC federation instead of stored AWS credentials.

```yaml
permissions:
  id-token: write  # Required for OIDC

- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ env.AWS_ROLE_ARN }}
```

**Why**:
- No long-lived secrets in GitHub
- Automatic credential rotation (15-60 min tokens)
- Fine-grained access control per repository/branch
- Audit trail in CloudTrail

**Alternative Considered**: GitHub Secrets with Access Keys
- ❌ Rejected: Requires manual rotation, higher breach risk

### Decision: Security Scanning in Pipeline

**Choice**: Run tfsec and Checkov on every PR.

**Why**:
- "Shift Left" security: Find issues before deployment
- Automated policy enforcement
- Educational: Developers learn security patterns
- Compliance evidence: Documented security reviews

---

## Cost Optimization

### Decision: Free Tier Compatible Instance Types

**Choice**: t3.micro for EC2, db.t3.micro for RDS.

**Why**:
- 750 hours/month free for first 12 months
- Sufficient for portfolio demonstration
- Easy to upgrade for production

### Decision: Single NAT Gateway Option

**Choice**: Configurable NAT Gateway count (1 or per-AZ).

```hcl
variable "enable_nat_gateway" {
  default = true  # Set to false for ~$32/month savings
}
```

**Why**:
- NAT Gateways are the most expensive component (~$32/month each)
- Single NAT acceptable for dev/demo environments
- Production should use per-AZ for high availability

### Decision: S3 Lifecycle Policies

**Choice**: Automatic deletion of ALB logs after 30 days.

**Why**:
- Prevents unbounded storage growth
- Balances audit requirements with cost
- Production might extend to 90+ days

---

---

## Operations & Observability

### Decision: CloudWatch Dashboard for Centralized Monitoring

**Choice**: Create a custom CloudWatch dashboard with all critical metrics.

**Why**:
- Single pane of glass for operations team
- Faster incident response with pre-built views
- Includes threshold annotations for context
- Shows alarm status at a glance

**Dashboard Sections**:
1. ALB metrics (requests, response time, errors)
2. EC2/ASG metrics (CPU, network, health)
3. RDS metrics (CPU, connections, IOPS, storage)
4. Active alarms widget

### Decision: AWS Config for Continuous Compliance

**Choice**: Implement AWS Config rules to continuously evaluate resource compliance.

**Rules Implemented**:
- EC2 detailed monitoring enabled
- RDS storage encrypted
- No unrestricted SSH access
- S3 bucket encryption
- VPC Flow Logs enabled
- Required tags present

**Why**:
- Continuous compliance monitoring (not point-in-time)
- Automated detection of configuration drift
- Audit trail for compliance reporting
- Aligns with CIS Benchmarks and AWS best practices

### Decision: Operational Runbooks in Repository

**Choice**: Store runbooks as markdown files in the repository, not external wiki.

**Why**:
- Version controlled with infrastructure code
- Pull requests for runbook changes
- Available offline during incidents
- Searchable via grep/IDE

**Runbook Structure**:
- Symptoms and diagnostic commands
- Step-by-step recovery procedures
- Verification commands
- Links to related runbooks

---

## Summary

These decisions demonstrate understanding of:

| Area | Key Principle |
|------|---------------|
| **Network** | Defense in depth, least privilege |
| **Security** | Zero trust, no hardcoded secrets |
| **State** | Collaboration, locking, encryption |
| **Compute** | Self-healing, immutable infrastructure |
| **Database** | Managed services, encryption |
| **CI/CD** | Shift-left security, OIDC auth |
| **Cost** | Free tier awareness, right-sizing |
| **Operations** | Runbooks, dashboards, drift detection |
| **Compliance** | Continuous monitoring, Config rules |

Each decision reflects real-world engineering trade-offs and AWS Well-Architected Framework principles.

