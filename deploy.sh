#!/bin/bash
# Deployment script for AWS CloudShell or local environment

set -e

echo "🚀 Terraform 3-Tier Web Application Deployment"
echo "=============================================="
echo ""

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo "⚠️  terraform.tfvars not found!"
    echo "📝 Creating terraform.tfvars from example..."
    cp terraform.tfvars.example terraform.tfvars
    echo ""
    echo "⚠️  IMPORTANT: Please edit terraform.tfvars and set your database password!"
    echo "   Then run this script again."
    exit 1
fi

# Check if db_password is set
if grep -q "db_password.*=.*\"\"" terraform.tfvars || ! grep -q "db_password" terraform.tfvars; then
    echo "⚠️  Database password not set in terraform.tfvars!"
    echo "   Please set db_password before deploying."
    exit 1
fi

# Initialize Terraform
echo "📦 Initializing Terraform..."
terraform init

# Validate configuration
echo ""
echo "✅ Validating Terraform configuration..."
terraform validate

# Plan deployment
echo ""
echo "📋 Planning deployment..."
terraform plan -out=tfplan

# Ask for confirmation
echo ""
read -p "🤔 Do you want to apply these changes? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "❌ Deployment cancelled."
    exit 0
fi

# Apply changes
echo ""
echo "🚀 Deploying infrastructure..."
terraform apply tfplan

# Show outputs
echo ""
echo "✅ Deployment complete!"
echo ""
echo "📊 Application Information:"
terraform output

echo ""
echo "🌐 Access your application at:"
terraform output -raw application_url

echo ""
echo "📝 Next steps:"
echo "   1. Wait 5-10 minutes for instances to initialize"
echo "   2. Access the application URL above"
echo "   3. Check CloudWatch Logs if issues occur"
echo ""
echo "🧹 To destroy all resources, run: terraform destroy"

