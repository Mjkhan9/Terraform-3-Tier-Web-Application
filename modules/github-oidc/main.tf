# ═══════════════════════════════════════════════════════════════════════════════
# GITHUB OIDC AUTHENTICATION MODULE
# ═══════════════════════════════════════════════════════════════════════════════
# This module enables password-less authentication from GitHub Actions to AWS
# using OpenID Connect (OIDC). This is the modern, secure approach that:
#
#   1. Eliminates long-lived AWS Access Keys in GitHub Secrets
#   2. Provides short-lived, auto-rotating credentials
#   3. Enables fine-grained access control per repository/branch
#   4. Creates audit trail via CloudTrail
#
# HOW IT WORKS:
#   1. GitHub Actions requests a JWT token from GitHub's OIDC provider
#   2. The workflow assumes the IAM Role using the JWT
#   3. AWS validates the JWT against the OIDC provider
#   4. AWS issues temporary credentials (15min-1hr)
#
# This approach is recommended by both AWS and GitHub for CI/CD pipelines.
# ═══════════════════════════════════════════════════════════════════════════════

# GitHub OIDC Provider (only create once per AWS account)
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]

  tags = {
    Name = "github-actions-oidc"
  }
}

# IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions" {
  name        = "${var.project_name}-github-actions-role"
  description = "Role assumed by GitHub Actions for Terraform deployments"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # Restrict to specific repository and branches
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-github-actions-role"
  }
}

# Policy for Terraform operations
resource "aws_iam_role_policy" "terraform_permissions" {
  name = "${var.project_name}-terraform-permissions"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformStateAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::terraform-state-*",
          "arn:aws:s3:::terraform-state-*/*"
        ]
      },
      {
        Sid    = "TerraformStateLocking"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:*:*:table/terraform-state-lock"
      },
      {
        Sid    = "TerraformPlanReadOnly"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "rds:Describe*",
          "s3:Get*",
          "s3:List*",
          "elasticloadbalancing:Describe*",
          "autoscaling:Describe*",
          "cloudwatch:Describe*",
          "cloudwatch:Get*",
          "cloudwatch:List*",
          "iam:Get*",
          "iam:List*",
          "sns:Get*",
          "sns:List*",
          "logs:Describe*",
          "logs:Get*",
          "secretsmanager:Describe*",
          "secretsmanager:List*"
        ]
        Resource = "*"
      }
      # Add more permissions for terraform apply if needed
      # For a portfolio project, read-only is safer
    ]
  })
}

