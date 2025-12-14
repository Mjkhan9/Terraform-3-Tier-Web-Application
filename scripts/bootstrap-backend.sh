#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Terraform Backend Bootstrap Script
# ═══════════════════════════════════════════════════════════════════════════════
# This script creates the S3 bucket and DynamoDB table required for remote state.
# Run this ONCE before enabling the backend configuration.
#
# Usage: ./scripts/bootstrap-backend.sh
# ═══════════════════════════════════════════════════════════════════════════════

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}"
echo "═══════════════════════════════════════════════════════════════"
echo "  Terraform Backend Bootstrap"
echo "═══════════════════════════════════════════════════════════════"
echo -e "${NC}"

# Get AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ Error: Could not get AWS Account ID. Check your AWS credentials.${NC}"
    exit 1
fi

REGION="${AWS_REGION:-us-east-1}"
BUCKET_NAME="terraform-state-3tier-app-${ACCOUNT_ID}"
DYNAMODB_TABLE="terraform-state-lock"

echo -e "${YELLOW}Configuration:${NC}"
echo "  Account ID:     $ACCOUNT_ID"
echo "  Region:         $REGION"
echo "  S3 Bucket:      $BUCKET_NAME"
echo "  DynamoDB Table: $DYNAMODB_TABLE"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Create S3 Bucket
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}Creating S3 bucket for Terraform state...${NC}"

if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    echo -e "${GREEN}✓ S3 bucket already exists${NC}"
else
    # Create bucket (different command for us-east-1)
    if [ "$REGION" = "us-east-1" ]; then
        aws s3api create-bucket \
            --bucket "$BUCKET_NAME" \
            --region "$REGION"
    else
        aws s3api create-bucket \
            --bucket "$BUCKET_NAME" \
            --region "$REGION" \
            --create-bucket-configuration LocationConstraint="$REGION"
    fi
    echo -e "${GREEN}✓ S3 bucket created${NC}"
fi

# Enable versioning
echo -e "${CYAN}Enabling S3 versioning...${NC}"
aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled
echo -e "${GREEN}✓ Versioning enabled${NC}"

# Enable encryption
echo -e "${CYAN}Enabling S3 encryption...${NC}"
aws s3api put-bucket-encryption \
    --bucket "$BUCKET_NAME" \
    --server-side-encryption-configuration '{
        "Rules": [
            {
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                },
                "BucketKeyEnabled": true
            }
        ]
    }'
echo -e "${GREEN}✓ Encryption enabled${NC}"

# Block public access
echo -e "${CYAN}Blocking public access...${NC}"
aws s3api put-public-access-block \
    --bucket "$BUCKET_NAME" \
    --public-access-block-configuration '{
        "BlockPublicAcls": true,
        "IgnorePublicAcls": true,
        "BlockPublicPolicy": true,
        "RestrictPublicBuckets": true
    }'
echo -e "${GREEN}✓ Public access blocked${NC}"

# ═══════════════════════════════════════════════════════════════════════════════
# Create DynamoDB Table
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}Creating DynamoDB table for state locking...${NC}"

if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$REGION" 2>/dev/null; then
    echo -e "${GREEN}✓ DynamoDB table already exists${NC}"
else
    aws dynamodb create-table \
        --table-name "$DYNAMODB_TABLE" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$REGION"
    
    echo -e "${YELLOW}Waiting for table to be active...${NC}"
    aws dynamodb wait table-exists --table-name "$DYNAMODB_TABLE" --region "$REGION"
    echo -e "${GREEN}✓ DynamoDB table created${NC}"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Output Configuration
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ Backend infrastructure created successfully!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo "1. Update backend.tf with your bucket name:"
echo ""
echo -e "${CYAN}terraform {
  backend \"s3\" {
    bucket         = \"$BUCKET_NAME\"
    key            = \"3-tier-web-app/terraform.tfstate\"
    region         = \"$REGION\"
    encrypt        = true
    dynamodb_table = \"$DYNAMODB_TABLE\"
  }
}${NC}"
echo ""
echo "2. Initialize Terraform with the new backend:"
echo -e "   ${CYAN}terraform init -migrate-state${NC}"
echo ""
echo "3. Verify state is stored remotely:"
echo -e "   ${CYAN}aws s3 ls s3://$BUCKET_NAME/${NC}"
echo ""

