# =============================================================================
# Grafana as Code — Makefile
# =============================================================================
# Manage your Grafana infrastructure with Terraform.
#
# Quick Start:
#   make init ENV=myenv
#   make plan ENV=myenv
#   make apply ENV=myenv
# =============================================================================

.PHONY: help init plan apply destroy fmt validate clean output vault-setup vault-verify

# Default environment — change this or override with: make plan ENV=staging
ENV ?= myenv

TF_VAR_FILE = environments/$(ENV).tfvars
TF_BACKEND  = backends/$(ENV).tfbackend

# ============================
# Help
# ============================

help:
	@echo "Grafana as Code — Terraform Management"
	@echo "======================================="
	@echo ""
	@echo "Usage: make <target> [ENV=myenv]"
	@echo ""
	@echo "Targets:"
	@echo "  init          Initialize Terraform for the specified environment"
	@echo "  plan          Generate and show an execution plan"
	@echo "  apply         Apply the planned changes"
	@echo "  destroy       Destroy all managed resources (requires confirmation)"
	@echo ""
	@echo "  fmt           Format all Terraform files"
	@echo "  validate      Validate Terraform configuration"
	@echo "  clean         Remove Terraform cache and plan files"
	@echo "  output        Show Terraform outputs"
	@echo "  state-list    List all resources in state"
	@echo ""
	@echo "  vault-setup   Setup Vault secrets for the environment"
	@echo "  vault-verify  Verify Vault secrets exist"
	@echo ""
	@echo "  ci-init       Initialize (CI/CD, non-interactive)"
	@echo "  ci-plan       Plan (CI/CD, non-interactive)"
	@echo "  ci-apply      Apply (CI/CD, auto-approve)"
	@echo "  ci-destroy    Destroy (CI/CD, auto-approve)"
	@echo ""
	@echo "Examples:"
	@echo "  make init ENV=myenv"
	@echo "  make plan ENV=myenv"
	@echo "  make apply ENV=myenv"
	@echo "  make vault-setup ENV=myenv"
	@echo ""
	@echo "Adding a new environment:"
	@echo "  1. Create environments/<name>.tfvars"
	@echo "  2. Create backends/<name>.tfbackend"
	@echo "  3. Create config/<name>/ (copy from config/myenv/)"
	@echo "  4. Create dashboards/<name>/ with org subdirectories"
	@echo "  5. Run: make init ENV=<name>"

# ============================
# Initialization
# ============================

init:
	@echo "Initializing Terraform for $(ENV)..."
	terraform init -backend-config=$(TF_BACKEND) -reconfigure

# ============================
# Planning
# ============================

plan:
	@echo "Planning changes for $(ENV)..."
	terraform plan -var-file=$(TF_VAR_FILE) -out=tfplan-$(ENV)

# ============================
# Applying
# ============================

apply:
	@echo "Applying changes for $(ENV)..."
	@if [ -f tfplan-$(ENV) ]; then \
		terraform apply tfplan-$(ENV); \
	else \
		terraform apply -var-file=$(TF_VAR_FILE); \
	fi

apply-auto:
	@echo "Auto-applying changes for $(ENV)..."
	terraform apply -var-file=$(TF_VAR_FILE) -auto-approve

# ============================
# Destruction
# ============================

destroy:
	@echo "WARNING: This will DESTROY all resources in $(ENV)!"
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

state-list:
	terraform state list

# ============================
# Vault Operations
# ============================

vault-setup:
	@echo "Setting up Vault secrets for $(ENV)..."
	bash vault/scripts/setup-secrets.sh $(ENV)

vault-verify:
	@echo "Verifying Vault secrets for $(ENV)..."
	bash vault/scripts/verify-secrets.sh $(ENV)

# ============================
# CI/CD Targets (non-interactive)
# ============================

ci-init:
	terraform init -backend-config=$(TF_BACKEND) -input=false

ci-plan:
	terraform plan -var-file=$(TF_VAR_FILE) -input=false -out=tfplan

ci-apply:
	terraform apply -input=false -auto-approve tfplan

ci-destroy:
	terraform destroy -var-file=$(TF_VAR_FILE) -input=false -auto-approve
