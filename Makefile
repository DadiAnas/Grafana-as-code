# =============================================================================
# Grafana as Code — Makefile
# =============================================================================
# Manage your Grafana infrastructure with Terraform.
#
# Quick Start:
#   make new-env NAME=staging GRAFANA_URL=https://grafana.example.com
#   make init ENV=staging
#   make plan ENV=staging
#   make apply ENV=staging
# =============================================================================

.PHONY: help init plan apply destroy fmt validate clean output state-list \
        vault-setup vault-verify new-env delete-env list-envs check-env \
        ci-init ci-plan ci-apply ci-destroy apply-auto

# Default environment — override with: make plan ENV=staging
ENV ?= myenv

TF_VAR_FILE = environments/$(ENV).tfvars
TF_BACKEND  = backends/$(ENV).tfbackend

# ============================
# Help
# ============================

help:
	@echo ""
	@echo "  ╔═══════════════════════════════════════════════════════════╗"
	@echo "  ║         Grafana as Code — Terraform Management           ║"
	@echo "  ╚═══════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "  Usage: make <target> [ENV=myenv] [NAME=<new-env>]"
	@echo ""
	@echo "  ─── Environment Management ────────────────────────────────"
	@echo "  new-env       Create a new environment         NAME=staging [GRAFANA_URL=...]"
	@echo "  delete-env    Delete an environment             NAME=staging"
	@echo "  list-envs     List all configured environments"
	@echo "  check-env     Validate environment is ready     ENV=staging"
	@echo ""
	@echo "  ─── Terraform Workflow ────────────────────────────────────"
	@echo "  init          Initialize Terraform              ENV=staging"
	@echo "  plan          Generate execution plan            ENV=staging"
	@echo "  apply         Apply planned changes              ENV=staging"
	@echo "  destroy       Destroy all resources (confirm)    ENV=staging"
	@echo ""
	@echo "  ─── Utilities ─────────────────────────────────────────────"
	@echo "  fmt           Format all Terraform files"
	@echo "  validate      Validate Terraform configuration"
	@echo "  clean         Remove Terraform cache and plans"
	@echo "  output        Show Terraform outputs             ENV=staging"
	@echo "  state-list    List all resources in state"
	@echo ""
	@echo "  ─── Vault ────────────────────────────────────────────────"
	@echo "  vault-setup   Create Vault secrets               ENV=staging"
	@echo "  vault-verify  Verify Vault secrets exist          ENV=staging"
	@echo ""
	@echo "  ─── CI/CD ────────────────────────────────────────────────"
	@echo "  ci-init       Initialize (non-interactive)"
	@echo "  ci-plan       Plan (non-interactive)"
	@echo "  ci-apply      Apply (auto-approve)"
	@echo "  ci-destroy    Destroy (auto-approve)"
	@echo ""
	@echo "  ─── Quick Start ──────────────────────────────────────────"
	@echo "  make new-env NAME=staging GRAFANA_URL=https://grafana.example.com"
	@echo "  make check-env ENV=staging"
	@echo "  make vault-setup ENV=staging"
	@echo "  make init ENV=staging"
	@echo "  make plan ENV=staging"
	@echo "  make apply ENV=staging"
	@echo ""

# =============================================================================
# ENVIRONMENT MANAGEMENT
# =============================================================================

# Create a new environment (scaffolds all files)
# Usage: make new-env NAME=staging
# Usage: make new-env NAME=production GRAFANA_URL=https://grafana.example.com
NAME ?=
GRAFANA_URL ?= http://localhost:3000

new-env:
	@if [ -z "$(NAME)" ]; then \
		echo ""; \
		echo "  Error: NAME is required"; \
		echo ""; \
		echo "  Usage:"; \
		echo "    make new-env NAME=staging"; \
		echo "    make new-env NAME=production GRAFANA_URL=https://grafana.example.com"; \
		echo ""; \
		exit 1; \
	fi
	@bash scripts/new-env.sh "$(NAME)" "$(GRAFANA_URL)"

# Delete an environment (removes scaffolded files, NOT infrastructure)
# Usage: make delete-env NAME=staging
delete-env:
	@if [ -z "$(NAME)" ]; then \
		echo ""; \
		echo "  Error: NAME is required"; \
		echo ""; \
		echo "  Usage: make delete-env NAME=staging"; \
		echo ""; \
		exit 1; \
	fi
	@bash scripts/delete-env.sh "$(NAME)"

# List all configured environments
list-envs:
	@bash scripts/list-envs.sh

# Validate an environment is ready for deployment
# Usage: make check-env ENV=staging
check-env:
	@bash scripts/check-env.sh "$(ENV)"

# =============================================================================
# TERRAFORM WORKFLOW
# =============================================================================

init:
	@echo "Initializing Terraform for $(ENV)..."
	terraform init -backend-config=$(TF_BACKEND) -reconfigure

plan:
	@echo "Planning changes for $(ENV)..."
	terraform plan -var-file=$(TF_VAR_FILE) -out=tfplan-$(ENV)

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

destroy:
	@echo "WARNING: This will DESTROY all resources in $(ENV)!"
	@read -p "Type the environment name to confirm: " confirm && [ "$$confirm" = "$(ENV)" ]
	terraform destroy -var-file=$(TF_VAR_FILE)

# =============================================================================
# UTILITIES
# =============================================================================

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

# =============================================================================
# VAULT OPERATIONS
# =============================================================================

vault-setup:
	@echo "Setting up Vault secrets for $(ENV)..."
	bash vault/scripts/setup-secrets.sh $(ENV)

vault-verify:
	@echo "Verifying Vault secrets for $(ENV)..."
	bash vault/scripts/verify-secrets.sh $(ENV)

# =============================================================================
# CI/CD TARGETS (non-interactive)
# =============================================================================

ci-init:
	terraform init -backend-config=$(TF_BACKEND) -input=false

ci-plan:
	terraform plan -var-file=$(TF_VAR_FILE) -input=false -out=tfplan

ci-apply:
	terraform apply -input=false -auto-approve tfplan

ci-destroy:
	terraform destroy -var-file=$(TF_VAR_FILE) -input=false -auto-approve
