# ═══════════════════════════════════════════════════════════════════════════════
# REMOTE STATE CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════
# 
# This file configures remote state management using S3 and DynamoDB.
# Remote state is CRITICAL for:
#   1. Team collaboration (single source of truth)
#   2. State locking (prevents race conditions)
#   3. Security (state files contain sensitive data)
#   4. CI/CD pipelines (GitOps workflows)
#
# SETUP INSTRUCTIONS:
# 1. Run: make bootstrap   (creates S3 bucket and DynamoDB table)
# 2. Uncomment the backend block below
# 3. Run: terraform init -migrate-state
#
# ═══════════════════════════════════════════════════════════════════════════════

# Uncomment after running 'make bootstrap' to create the backend resources
# terraform {
#   backend "s3" {
#     bucket         = "terraform-state-3tier-app-ACCOUNT_ID"  # Replace ACCOUNT_ID
#     key            = "3-tier-web-app/terraform.tfstate"
#     region         = "us-east-1"
#     encrypt        = true
#     dynamodb_table = "terraform-state-lock"
#     
#     # Optional: Use a specific KMS key for encryption
#     # kms_key_id = "alias/terraform-state-key"
#   }
# }

# ═══════════════════════════════════════════════════════════════════════════════
# WHY REMOTE STATE MATTERS (For Portfolio Discussion)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Local State Problems:
#   - State files contain secrets in plain text (DB passwords, etc.)
#   - No collaboration - each engineer has different state
#   - No locking - concurrent applies can corrupt state
#   - Lost laptop = lost infrastructure knowledge
#
# S3 + DynamoDB Solution:
#   - S3: Versioned, encrypted storage for state file
#   - DynamoDB: Distributed locking prevents race conditions
#   - IAM: Fine-grained access control to state
#   - CloudTrail: Audit log of all state operations
#
# This pattern is used by 95%+ of production Terraform deployments.
# ═══════════════════════════════════════════════════════════════════════════════

