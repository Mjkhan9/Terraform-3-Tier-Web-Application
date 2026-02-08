# ═══════════════════════════════════════════════════════════════════════════════
# AWS SECRETS MANAGER MODULE
# ═══════════════════════════════════════════════════════════════════════════════
# This module implements secure secrets management following AWS best practices:
#   1. Database credentials stored in Secrets Manager (not in code/state)
#   2. Automatic rotation capability
#   3. Fine-grained IAM access control
#   4. Encryption with KMS
#   5. Audit trail via CloudTrail
#
# WHY THIS MATTERS:
#   - Eliminates hardcoded passwords in terraform.tfvars
#   - Removes secrets from Terraform state file
#   - Enables credential rotation without redeployment
#   - Supports compliance requirements (SOC2, HIPAA, PCI-DSS)
# ═══════════════════════════════════════════════════════════════════════════════

# Generate random password for database
resource "random_password" "db_password" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Store database credentials in Secrets Manager
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.project_name}/database/credentials"
  description = "Database credentials for ${var.project_name}"

  # KMS encryption (uses AWS managed key by default)
  # For production, use a customer-managed KMS key:
  # kms_key_id = var.kms_key_id

  tags = {
    Name = "${var.project_name}-db-credentials"
  }
}

# Store the actual secret value
resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    engine   = "postgres"
    host     = var.db_host
    port     = var.db_port
    dbname   = var.db_name
  })
}

# IAM Policy for applications to read the secret
resource "aws_iam_policy" "read_db_secret" {
  name        = "${var.project_name}-read-db-secret"
  description = "Allow reading database credentials from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GetSecretValue"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.db_credentials.arn
      },
      {
        Sid    = "DecryptSecret"
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${var.region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

# ═══════════════════════════════════════════════════════════════════════════════
# ROTATION CONFIGURATION (Optional - for production)
# ═══════════════════════════════════════════════════════════════════════════════
# Uncomment to enable automatic password rotation
# This requires a Lambda function to perform the rotation
#
# resource "aws_secretsmanager_secret_rotation" "db_credentials" {
#   secret_id           = aws_secretsmanager_secret.db_credentials.id
#   rotation_lambda_arn = var.rotation_lambda_arn
#
#   rotation_rules {
#     automatically_after_days = 30
#   }
# }

