# ═══════════════════════════════════════════════════════════════════════════════
# Terraform 3-Tier Web Application - Makefile
# ═══════════════════════════════════════════════════════════════════════════════
# Usage: make <target>
# Run 'make help' for available commands
# ═══════════════════════════════════════════════════════════════════════════════

.PHONY: help init plan apply destroy fmt validate clean docs security cost

# Default target
.DEFAULT_GOAL := help

# Colors for output
CYAN := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
RESET := \033[0m

# ═══════════════════════════════════════════════════════════════════════════════
# HELP
# ═══════════════════════════════════════════════════════════════════════════════

help: ## Show this help message
	@echo ""
	@echo "$(CYAN)═══════════════════════════════════════════════════════════════$(RESET)"
	@echo "$(CYAN)  Terraform 3-Tier Web Application$(RESET)"
	@echo "$(CYAN)═══════════════════════════════════════════════════════════════$(RESET)"
	@echo ""
	@echo "$(YELLOW)Available commands:$(RESET)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-15s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Examples:$(RESET)"
	@echo "  make init      # Initialize Terraform"
	@echo "  make plan      # Preview changes"
	@echo "  make apply     # Deploy infrastructure"
	@echo "  make destroy   # Tear down infrastructure"
	@echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TERRAFORM COMMANDS
# ═══════════════════════════════════════════════════════════════════════════════

init: ## Initialize Terraform (download providers)
	@echo "$(CYAN)🔧 Initializing Terraform...$(RESET)"
	@terraform init
	@echo "$(GREEN)✅ Terraform initialized$(RESET)"

plan: init ## Preview infrastructure changes
	@echo "$(CYAN)📋 Planning infrastructure changes...$(RESET)"
	@terraform plan -out=tfplan
	@echo "$(GREEN)✅ Plan complete. Review changes above.$(RESET)"

apply: ## Apply infrastructure changes (requires plan first)
	@echo "$(CYAN)🚀 Applying infrastructure changes...$(RESET)"
	@if [ -f tfplan ]; then \
		terraform apply tfplan; \
	else \
		terraform apply; \
	fi
	@echo "$(GREEN)✅ Infrastructure deployed!$(RESET)"

apply-auto: init ## Apply changes without confirmation (use with caution!)
	@echo "$(YELLOW)⚠️  Auto-applying without confirmation...$(RESET)"
	@terraform apply -auto-approve
	@echo "$(GREEN)✅ Infrastructure deployed!$(RESET)"

destroy: ## Destroy all infrastructure
	@echo "$(RED)🗑️  Destroying infrastructure...$(RESET)"
	@terraform destroy
	@echo "$(GREEN)✅ Infrastructure destroyed$(RESET)"

destroy-auto: ## Destroy without confirmation (use with caution!)
	@echo "$(RED)⚠️  Auto-destroying without confirmation...$(RESET)"
	@terraform destroy -auto-approve
	@echo "$(GREEN)✅ Infrastructure destroyed$(RESET)"

# ═══════════════════════════════════════════════════════════════════════════════
# CODE QUALITY
# ═══════════════════════════════════════════════════════════════════════════════

fmt: ## Format Terraform files
	@echo "$(CYAN)🖌️  Formatting Terraform files...$(RESET)"
	@terraform fmt -recursive
	@echo "$(GREEN)✅ Files formatted$(RESET)"

fmt-check: ## Check if files are formatted
	@echo "$(CYAN)🔍 Checking Terraform formatting...$(RESET)"
	@terraform fmt -check -recursive
	@echo "$(GREEN)✅ All files properly formatted$(RESET)"

validate: init ## Validate Terraform configuration
	@echo "$(CYAN)✅ Validating Terraform configuration...$(RESET)"
	@terraform validate
	@echo "$(GREEN)✅ Configuration is valid$(RESET)"

lint: fmt validate ## Run all linting (format + validate)
	@echo "$(GREEN)✅ All linting checks passed$(RESET)"

# ═══════════════════════════════════════════════════════════════════════════════
# SECURITY
# ═══════════════════════════════════════════════════════════════════════════════

security: ## Run security scan with tfsec
	@echo "$(CYAN)🔒 Running security scan...$(RESET)"
	@if command -v tfsec &> /dev/null; then \
		tfsec . --format lovely; \
	else \
		echo "$(YELLOW)⚠️  tfsec not installed. Install with: brew install tfsec$(RESET)"; \
		echo "$(YELLOW)   Or: go install github.com/aquasecurity/tfsec/cmd/tfsec@latest$(RESET)"; \
	fi

checkov: ## Run security scan with Checkov
	@echo "$(CYAN)🛡️  Running Checkov security scan...$(RESET)"
	@if command -v checkov &> /dev/null; then \
		checkov -d . --framework terraform; \
	else \
		echo "$(YELLOW)⚠️  Checkov not installed. Install with: pip install checkov$(RESET)"; \
	fi

# ═══════════════════════════════════════════════════════════════════════════════
# COST ESTIMATION
# ═══════════════════════════════════════════════════════════════════════════════

cost: init ## Estimate infrastructure costs
	@echo "$(CYAN)💰 Estimating infrastructure costs...$(RESET)"
	@if command -v infracost &> /dev/null; then \
		infracost breakdown --path .; \
	else \
		echo ""; \
		echo "$(YELLOW)Estimated Monthly Cost (outside Free Tier):$(RESET)"; \
		echo "  ├── NAT Gateways (2x):     ~\$$64/month"; \
		echo "  ├── ALB:                   ~\$$16/month"; \
		echo "  ├── EC2 t3.micro (2x):     ~\$$15/month"; \
		echo "  ├── RDS db.t3.micro:       ~\$$15/month"; \
		echo "  ├── S3 + Data Transfer:    ~\$$5/month"; \
		echo "  └────────────────────────────────────"; \
		echo "  $(GREEN)Total Estimate:            ~\$$115/month$(RESET)"; \
		echo ""; \
		echo "$(CYAN)💡 For detailed cost breakdown, install Infracost:$(RESET)"; \
		echo "   brew install infracost && infracost auth login"; \
	fi

# ═══════════════════════════════════════════════════════════════════════════════
# DOCUMENTATION
# ═══════════════════════════════════════════════════════════════════════════════

docs: ## Generate Terraform documentation
	@echo "$(CYAN)📚 Generating documentation...$(RESET)"
	@if command -v terraform-docs &> /dev/null; then \
		terraform-docs markdown table . > TERRAFORM_DOCS.md; \
		echo "$(GREEN)✅ Documentation generated: TERRAFORM_DOCS.md$(RESET)"; \
	else \
		echo "$(YELLOW)⚠️  terraform-docs not installed.$(RESET)"; \
		echo "$(YELLOW)   Install with: brew install terraform-docs$(RESET)"; \
	fi

# ═══════════════════════════════════════════════════════════════════════════════
# UTILITIES
# ═══════════════════════════════════════════════════════════════════════════════

clean: ## Clean up temporary files
	@echo "$(CYAN)🧹 Cleaning up...$(RESET)"
	@rm -rf .terraform
	@rm -f .terraform.lock.hcl
	@rm -f tfplan
	@rm -f *.tfstate*
	@rm -f crash.log
	@echo "$(GREEN)✅ Cleaned up$(RESET)"

output: ## Show Terraform outputs
	@echo "$(CYAN)📊 Terraform Outputs:$(RESET)"
	@terraform output

state: ## Show Terraform state list
	@echo "$(CYAN)📋 Terraform State:$(RESET)"
	@terraform state list

refresh: ## Refresh Terraform state
	@echo "$(CYAN)🔄 Refreshing state...$(RESET)"
	@terraform refresh
	@echo "$(GREEN)✅ State refreshed$(RESET)"

# ═══════════════════════════════════════════════════════════════════════════════
# CI/CD SIMULATION
# ═══════════════════════════════════════════════════════════════════════════════

ci: fmt-check validate security ## Run CI checks locally (format, validate, security)
	@echo ""
	@echo "$(GREEN)═══════════════════════════════════════════════════$(RESET)"
	@echo "$(GREEN)  ✅ All CI checks passed!$(RESET)"
	@echo "$(GREEN)═══════════════════════════════════════════════════$(RESET)"

# ═══════════════════════════════════════════════════════════════════════════════
# QUICK START
# ═══════════════════════════════════════════════════════════════════════════════

setup: ## First-time setup (copy tfvars, init)
	@echo "$(CYAN)🚀 Setting up project...$(RESET)"
	@if [ ! -f terraform.tfvars ]; then \
		cp terraform.tfvars.example terraform.tfvars; \
		echo "$(YELLOW)⚠️  Created terraform.tfvars - please edit and set your db_password!$(RESET)"; \
	fi
	@$(MAKE) init
	@echo ""
	@echo "$(GREEN)✅ Setup complete!$(RESET)"
	@echo "$(CYAN)Next steps:$(RESET)"
	@echo "  1. Edit terraform.tfvars and set db_password"
	@echo "  2. Run 'make plan' to preview changes"
	@echo "  3. Run 'make apply' to deploy"

all: lint security plan ## Run all checks and create plan
	@echo "$(GREEN)✅ All checks complete. Run 'make apply' to deploy.$(RESET)"

# ═══════════════════════════════════════════════════════════════════════════════
# REMOTE STATE BOOTSTRAP
# ═══════════════════════════════════════════════════════════════════════════════

bootstrap: ## Create S3 bucket and DynamoDB table for remote state
	@echo "$(CYAN)🔧 Bootstrapping Terraform backend...$(RESET)"
	@chmod +x scripts/bootstrap-backend.sh
	@./scripts/bootstrap-backend.sh

