# ═══════════════════════════════════════════════════════════════════════════════
# AWS CONFIG - CONTINUOUS COMPLIANCE MONITORING
# ═══════════════════════════════════════════════════════════════════════════════
# This module sets up AWS Config rules to continuously evaluate resource 
# compliance against security and operational best practices.
#
# Rules implemented:
# - EC2 instances must have detailed monitoring enabled
# - RDS storage must be encrypted
# - Security groups should not allow unrestricted SSH
# - S3 buckets should have encryption enabled
# - VPC Flow Logs must be enabled
# ═══════════════════════════════════════════════════════════════════════════════

# IAM Role for AWS Config
resource "aws_iam_role" "config" {
  name = "${var.project_name}-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-config-role"
  }
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# S3 Bucket for Config Delivery
resource "aws_s3_bucket" "config" {
  bucket = "${var.project_name}-config-${random_id.bucket_suffix.hex}"

  tags = {
    Name = "${var.project_name}-config-bucket"
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket = aws_s3_bucket.config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config.arn
      },
      {
        Sid    = "AWSConfigBucketExistenceCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.config.arn
      },
      {
        Sid    = "AWSConfigBucketDelivery"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# ═══════════════════════════════════════════════════════════════════════════════
# AWS CONFIG RECORDER
# ═══════════════════════════════════════════════════════════════════════════════

resource "aws_config_configuration_recorder" "main" {
  name     = "${var.project_name}-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "${var.project_name}-delivery-channel"
  s3_bucket_name = aws_s3_bucket.config.bucket

  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIG RULES - SECURITY & COMPLIANCE
# ═══════════════════════════════════════════════════════════════════════════════

# Rule 1: EC2 Detailed Monitoring
# Ensures all EC2 instances have detailed monitoring enabled for better observability
resource "aws_config_config_rule" "ec2_detailed_monitoring" {
  name        = "${var.project_name}-ec2-detailed-monitoring"
  description = "Checks whether detailed monitoring is enabled for EC2 instances"

  source {
    owner             = "AWS"
    source_identifier = "EC2_INSTANCE_DETAILED_MONITORING_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = {
    Name       = "${var.project_name}-ec2-detailed-monitoring"
    Compliance = "operational-excellence"
  }
}

# Rule 2: RDS Encryption
# Ensures RDS instances have storage encryption enabled (compliance requirement)
resource "aws_config_config_rule" "rds_encryption" {
  name        = "${var.project_name}-rds-storage-encrypted"
  description = "Checks whether storage encryption is enabled for RDS instances"

  source {
    owner             = "AWS"
    source_identifier = "RDS_STORAGE_ENCRYPTED"
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = {
    Name       = "${var.project_name}-rds-storage-encrypted"
    Compliance = "security"
  }
}

# Rule 3: Restricted SSH
# Ensures security groups don't allow unrestricted SSH access (0.0.0.0/0:22)
resource "aws_config_config_rule" "restricted_ssh" {
  name        = "${var.project_name}-restricted-ssh"
  description = "Checks whether security groups allow unrestricted SSH access"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = {
    Name       = "${var.project_name}-restricted-ssh"
    Compliance = "security"
  }
}

# Rule 4: S3 Bucket Encryption
# Ensures all S3 buckets have server-side encryption enabled
resource "aws_config_config_rule" "s3_encryption" {
  name        = "${var.project_name}-s3-bucket-encryption"
  description = "Checks whether S3 buckets have server-side encryption enabled"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = {
    Name       = "${var.project_name}-s3-bucket-encryption"
    Compliance = "security"
  }
}

# Rule 5: VPC Flow Logs
# Ensures VPC Flow Logs are enabled for network traffic visibility
resource "aws_config_config_rule" "vpc_flow_logs" {
  name        = "${var.project_name}-vpc-flow-logs"
  description = "Checks whether VPC Flow Logs are enabled"

  source {
    owner             = "AWS"
    source_identifier = "VPC_FLOW_LOGS_ENABLED"
  }

  input_parameters = jsonencode({
    trafficType = "ALL"
  })

  depends_on = [aws_config_configuration_recorder.main]

  tags = {
    Name       = "${var.project_name}-vpc-flow-logs"
    Compliance = "security"
  }
}

# Rule 6: RDS Multi-AZ
# Checks if RDS instances are configured for Multi-AZ (production requirement)
resource "aws_config_config_rule" "rds_multi_az" {
  name        = "${var.project_name}-rds-multi-az"
  description = "Checks whether RDS instances are configured for Multi-AZ"

  source {
    owner             = "AWS"
    source_identifier = "RDS_MULTI_AZ_SUPPORT"
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = {
    Name       = "${var.project_name}-rds-multi-az"
    Compliance = "reliability"
  }
}

# Rule 7: Required Tags
# Ensures all resources have required tags for cost allocation and ownership
resource "aws_config_config_rule" "required_tags" {
  name        = "${var.project_name}-required-tags"
  description = "Checks whether resources have required tags"

  source {
    owner             = "AWS"
    source_identifier = "REQUIRED_TAGS"
  }

  input_parameters = jsonencode({
    tag1Key = "Project"
    tag2Key = "Environment"
    tag3Key = "ManagedBy"
  })

  depends_on = [aws_config_configuration_recorder.main]

  tags = {
    Name       = "${var.project_name}-required-tags"
    Compliance = "governance"
  }
}

# Rule 8: EBS Encryption
# Ensures all EBS volumes are encrypted
resource "aws_config_config_rule" "ebs_encryption" {
  name        = "${var.project_name}-ebs-encryption"
  description = "Checks whether EBS volumes are encrypted"

  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = {
    Name       = "${var.project_name}-ebs-encryption"
    Compliance = "security"
  }
}

# Rule 9: ALB WAF Enabled (if WAF is used)
# Checks if WAF is associated with ALB
resource "aws_config_config_rule" "alb_waf" {
  name        = "${var.project_name}-alb-waf-enabled"
  description = "Checks whether WAF is enabled on Application Load Balancers"

  source {
    owner             = "AWS"
    source_identifier = "ALB_WAF_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = {
    Name       = "${var.project_name}-alb-waf-enabled"
    Compliance = "security"
  }
}

# Rule 10: CloudTrail Enabled
# Ensures CloudTrail is enabled for API auditing
resource "aws_config_config_rule" "cloudtrail_enabled" {
  name        = "${var.project_name}-cloudtrail-enabled"
  description = "Checks whether CloudTrail is enabled in the AWS account"

  source {
    owner             = "AWS"
    source_identifier = "CLOUD_TRAIL_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = {
    Name       = "${var.project_name}-cloudtrail-enabled"
    Compliance = "security"
  }
}

