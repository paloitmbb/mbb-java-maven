.PHONY: help pre-commit pre-commit-install pre-commit-update pre-commit-clean fmt validate lint security file-checks init plan apply clean check

# Default target - show help
help:
	@echo "Available targets:"
	@echo "  make help                - Show this help message"
	@echo ""
	@echo "Pre-commit Commands:"
	@echo "  make pre-commit          - Run pre-commit on all files"
	@echo "  make pre-commit-install  - Install pre-commit hooks"
	@echo "  make pre-commit-update   - Update pre-commit hook versions"
	@echo "  make pre-commit-clean    - Clean pre-commit cache"
	@echo ""
	@echo "Terraform Commands:"
	@echo "  make fmt                 - Format Terraform code"
	@echo "  make validate            - Validate Terraform configuration"
	@echo "  make lint                - Run tflint"
	@echo "  make security            - Run security scans (tfsec + trivy)"
	@echo "  make file-checks         - Run file checks (YAML, large files, merge conflicts, secrets)"
	@echo "  make init ENV=dev        - Initialize Terraform for environment"
	@echo "  make plan ENV=dev        - Run Terraform plan for environment"
	@echo "  make apply ENV=dev       - Apply Terraform changes for environment"
	@echo ""
	@echo "Utility Commands:"
	@echo "  make clean               - Clean Terraform cache files"
	@echo "  make check               - Run all checks (fmt, validate, lint, security, file-checks)"
	@echo ""
	@echo "Examples:"
	@echo "  make pre-commit          # Run all pre-commit hooks"
	@echo "  make init ENV=dev        # Initialize dev environment"
	@echo "  make plan ENV=staging    # Plan staging changes"

# Pre-commit targets
pre-commit:
	@echo "🔍 Running pre-commit on all files..."
	pre-commit run --all-files

pre-commit-install:
	@echo "📦 Installing pre-commit hooks..."
	pre-commit install
	@echo "✅ Pre-commit hooks installed"

pre-commit-update:
	@echo "⬆️  Updating pre-commit hooks..."
	pre-commit autoupdate

pre-commit-clean:
	@echo "🧹 Cleaning pre-commit cache..."
	pre-commit clean

# Terraform formatting
fmt:
	@echo "🎨 Formatting Terraform code via pre-commit..."
	pre-commit run terraform_fmt --all-files --verbose || true

# Terraform validation
validate:
	@echo "✅ Validating Terraform configuration via pre-commit..."
	pre-commit run terraform_validate --all-files --verbose || true

# TFLint
lint:
	@echo "🔍 Running tflint via pre-commit..."
	pre-commit run terraform_tflint --all-files --verbose || true

# Security scanning
security:
	@echo "🔒 Running security scans via pre-commit..."
	pre-commit run terraform_tfsec --all-files --verbose || true
	@echo ""
	pre-commit run terraform_trivy --all-files --verbose || true

# File checks
file-checks:
	@echo "📋 Running file checks via pre-commit..."
	pre-commit run trailing-whitespace --all-files --verbose || true
	pre-commit run end-of-file-fixer --all-files --verbose || true
	pre-commit run check-yaml --all-files --verbose || true
	pre-commit run check-added-large-files --all-files --verbose || true
	pre-commit run check-merge-conflict --all-files --verbose || true
	pre-commit run detect-private-key --all-files --verbose || true
	pre-commit run check-case-conflict --all-files --verbose || true
	pre-commit run mixed-line-ending --all-files --verbose || true
	pre-commit run check-github-actions --all-files --verbose || true

# Terraform initialization
init:
ifndef ENV
	@echo "❌ Error: ENV parameter required"
	@echo "Usage: make init ENV=dev|staging|production"
	@exit 1
endif
	@echo "🚀 Initializing Terraform for $(ENV) environment..."
	./scripts/init.sh $(ENV)

# Terraform plan
plan:
ifndef ENV
	@echo "❌ Error: ENV parameter required"
	@echo "Usage: make plan ENV=dev|staging|production"
	@exit 1
endif
	@echo "📋 Running Terraform plan for $(ENV) environment..."
	./scripts/plan.sh $(ENV)

# Terraform apply
apply:
ifndef ENV
	@echo "❌ Error: ENV parameter required"
	@echo "Usage: make apply ENV=dev|staging|production"
	@exit 1
endif
	@echo "🚀 Applying Terraform changes for $(ENV) environment..."
	./scripts/apply.sh $(ENV)

# Clean Terraform cache
# clean:
# 	@echo "🧹 Cleaning Terraform cache files..."
# 	find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
# 	find . -type f -name ".terraform.lock.hcl" -path "*/modules/*" -delete 2>/dev/null || true
# 	@echo "✅ Cache cleaned"

# Run all checks
check: fmt validate lint security file-checks
	@echo ""
	@echo "✅ All checks completed"
