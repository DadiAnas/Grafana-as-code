# Grafana as Code - Makefile
# ============================

.PHONY: help init plan apply destroy fmt validate clean

# Default target
help:
	@echo "Grafana as Code - Terraform Management"
	@echo "======================================="
	@echo ""
	@echo "Usage: make <target> [ENV=npr|preprod|prod]"
	@echo ""
	@echo "Initialization:"
	@echo "  init              Initialize Terraform for specified environment"
	@echo "  init-npr          Initialize for NPR environment"
	@echo "  init-preprod      Initialize for PreProd environment"
	@echo "  init-prod         Initialize for Production environment"
	@echo ""
	@echo "Planning:"
	@echo "  plan              Plan changes for specified environment"
	@echo "  plan-npr          Plan for NPR environment"
	@echo "  plan-preprod      Plan for PreProd environment"
	@echo "  plan-prod         Plan for Production environment"
	@echo ""
	@echo "Applying:"
	@echo "  apply             Apply changes for specified environment"
	@echo "  apply-npr         Apply for NPR environment"
	@echo "  apply-preprod     Apply for PreProd environment"
	@echo "  apply-prod        Apply for Production environment"
	@echo ""
	@echo "Destruction:"
	@echo "  destroy           Destroy resources (requires confirmation)"
	@echo ""
	@echo "Utilities:"
	@echo "  fmt               Format Terraform files"
	@echo "  validate          Validate Terraform configuration"
	@echo "  clean             Clean Terraform cache"
	@echo "  output            Show Terraform outputs"
	@echo ""
	@echo "Vault:"
	@echo "  vault-setup-npr   Setup Vault secrets for NPR"
	@echo "  vault-setup-preprod Setup Vault secrets for PreProd"
	@echo "  vault-setup-prod  Setup Vault secrets for Production"
	@echo "  vault-verify      Verify Vault secrets exist"
	@echo ""
	@echo "Examples:"
	@echo "  make init-npr"
	@echo "  make plan ENV=preprod"
	@echo "  make apply-prod"

# ============================
# Environment Variables
# ============================

ENV ?= npr
TF_VAR_FILE = environments/$(ENV).tfvars
TF_BACKEND = backends/$(ENV).tfbackend

# ============================
# Initialization
# ============================

init:
	@echo "Initializing Terraform for $(ENV) environment..."
	terraform init -backend-config=$(TF_BACKEND) -reconfigure

init-npr:
	@$(MAKE) init ENV=npr

init-preprod:
	@$(MAKE) init ENV=preprod

init-prod:
	@$(MAKE) init ENV=prod

# ============================
# Planning
# ============================

plan:
	@echo "Planning changes for $(ENV) environment..."
	terraform plan -var-file=$(TF_VAR_FILE) -out=tfplan-$(ENV)

plan-npr:
	@$(MAKE) plan ENV=npr

plan-preprod:
	@$(MAKE) plan ENV=preprod

plan-prod:
	@$(MAKE) plan ENV=prod

# ============================
# Applying
# ============================

apply:
	@echo "Applying changes for $(ENV) environment..."
	@if [ -f tfplan-$(ENV) ]; then \
		terraform apply tfplan-$(ENV); \
	else \
		terraform apply -var-file=$(TF_VAR_FILE); \
	fi

apply-npr:
	@$(MAKE) apply ENV=npr

apply-preprod:
	@$(MAKE) apply ENV=preprod

apply-prod:
	@echo "WARNING: You are applying to PRODUCTION!"
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ]
	@$(MAKE) apply ENV=prod

# ============================
# Auto-approve (for CI/CD)
# ============================

apply-auto:
	@echo "Auto-applying changes for $(ENV) environment..."
	terraform apply -var-file=$(TF_VAR_FILE) -auto-approve

# ============================
# Destruction
# ============================

destroy:
	@echo "WARNING: This will destroy all resources in $(ENV)!"
	@read -p "Type the environment name to confirm: " confirm && [ "$$confirm" = "$(ENV)" ]
	terraform destroy -var-file=$(TF_VAR_FILE)

# ============================
# Utilities
# ============================

fmt:
	@echo "Formatting Terraform files..."
	terraform fmt -recursive

validate:
	@echo "Validating Terraform configuration..."
	terraform validate

clean:
	@echo "Cleaning Terraform cache..."
	rm -rf .terraform
	rm -f .terraform.lock.hcl
	rm -f tfplan-*
	rm -f *.tfplan

output:
	@echo "Terraform outputs for $(ENV):"
	terraform output

output-summary:
	terraform output deployment_summary

# ============================
# State Management
# ============================

state-list:
	terraform state list

# ============================
# Vault Operations
# ============================

vault-setup-npr:
	@echo "Setting up Vault secrets for NPR..."
	./vault/scripts/setup-npr-secrets.sh

vault-setup-preprod:
	@echo "Setting up Vault secrets for PreProd..."
	./vault/scripts/setup-preprod-secrets.sh

vault-setup-prod:
	@echo "Setting up Vault secrets for Production..."
	./vault/scripts/setup-prod-secrets.sh

vault-setup-all:
	@echo "Setting up Vault secrets for all environments..."
	./vault/scripts/setup-all-secrets.sh --all

vault-verify:
	@echo "Verifying Vault secrets for $(ENV)..."
	./vault/scripts/verify-secrets.sh $(ENV)

# ============================
# CI/CD Targets
# ============================

ci-init:
	terraform init -backend-config=$(TF_BACKEND) -input=false

ci-plan:
	terraform plan -var-file=$(TF_VAR_FILE) -input=false -out=tfplan

ci-apply:
	terraform apply -input=false -auto-approve tfplan

ci-destroy:
	terraform destroy -var-file=$(TF_VAR_FILE) -input=false -auto-approve
