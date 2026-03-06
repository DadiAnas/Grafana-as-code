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

.PHONY: help init plan apply destroy fmt validate validate-config clean output state-list \
        vault-setup vault-verify new-env delete-env list-envs check-env \
        ci-init ci-plan ci-apply ci-destroy apply-auto \
        dev-up dev-down dev-bootstrap lint import drift backup promote \
        dashboard-diff test dry-run pre-commit-install pre-commit-run

# Default environment — override with: make plan ENV=staging
ENV ?= myenv

# Paths (new structure)
TF_DIR      = terraform
TF_VAR_FILE = ../envs/$(ENV)/terraform.tfvars
TF_BACKEND  = ../envs/$(ENV)/backend.tfbackend

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
	@echo "  new-env       Create a new environment         NAME=staging [options]"
	@echo "  delete-env    Delete an environment             NAME=staging"
	@echo "  list-envs     List all configured environments"
	@echo "  check-env     Validate environment is ready     ENV=staging"
	@echo ""
	@echo "  new-env options:"
	@echo "    NAME           (required) Environment name"
	@echo "    GRAFANA_URL    Grafana URL           (default: http://localhost:3000)"
	@echo "    VAULT_ADDR     Vault address          (default: http://localhost:8200)"
	@echo "    VAULT_MOUNT    Vault mount path       (default: grafana)"
	@echo "    KEYCLOAK_URL   Keycloak URL           (enables SSO config)"
	@echo "    BACKEND        Backend type           (s3 | azurerm | gcs | gitlab)"
	@echo "    ORGS           Organizations          (comma-separated)"
	@echo "    DATASOURCES    Datasource presets     (prometheus,loki,postgres,...)"
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
	@echo "  validate-config  Schema-validate all YAML config files [ENV=prod]"
	@echo "  lint          Run TFLint + YAML lint + schema validation"
	@echo "  pre-commit-install  Install git pre-commit hooks"
	@echo "  pre-commit-run      Run all pre-commit hooks on all files"
	@echo "  clean         Remove Terraform cache and plans"
	@echo "  output        Show Terraform outputs             ENV=staging"
	@echo "  state-list    List all resources in state"
	@echo ""
	@echo "  ─── Operations ───────────────────────────────────────────"
	@echo "  drift          Detect out-of-band changes        ENV=staging"
	@echo "  backup         Backup Grafana state via API      ENV=staging"
	@echo "  import         Import from existing Grafana      ENV=staging AUTH=admin:admin"
	@echo "                   Optional: NO_TF_IMPORT=true  NO_DASHBOARDS=true"
	@echo "  promote        Promote configs between envs      FROM=staging TO=prod"
	@echo "  dashboard-diff Human-readable dashboard diff     ENV=staging"
	@echo "  team-sync      Sync Keycloak groups → teams      ENV=prod GRAFANA_URL=... AUTH=..."
	@echo "                                                   KEYCLOAK_URL=... KEYCLOAK_USER=... KEYCLOAK_PASS=..."
	@echo ""
	@echo "  ─── Local Development ────────────────────────────────────"
	@echo "  dev-up         Start Grafana+Vault+Keycloak      (docker compose)"
	@echo "  dev-down       Stop local dev services"
	@echo "  dev-bootstrap  Bootstrap dev env (seed Vault)    "
	@echo "  test           Full local test cycle"
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
	@echo "  make new-env NAME=prod BACKEND=s3 DATASOURCES=prometheus,loki,postgres"
	@echo "  make check-env ENV=staging"
	@echo "  make vault-setup ENV=staging"
	@echo "  make init ENV=staging && make plan ENV=staging && make apply ENV=staging"
	@echo ""

# =============================================================================
# ENVIRONMENT MANAGEMENT
# =============================================================================

# Create a new environment (scaffolds all files)
#   Required:  NAME
#   Optional:  GRAFANA_URL, VAULT_ADDR, VAULT_MOUNT, KEYCLOAK_URL,
#              BACKEND (s3|azurerm|gcs|gitlab), ORGS, DATASOURCES
NAME         ?=
GRAFANA_URL  ?=
VAULT_ADDR   ?=
VAULT_MOUNT  ?=
KEYCLOAK_URL ?=
BACKEND      ?=
ORGS         ?=
DATASOURCES  ?=

new-env:
	@if [ -z "$(NAME)" ]; then \
		echo ""; \
		echo "  Error: NAME is required"; \
		echo ""; \
		echo "  Usage:"; \
		echo "    make new-env NAME=staging"; \
		echo "    make new-env NAME=prod GRAFANA_URL=https://grafana.example.com BACKEND=s3"; \
		echo "    make new-env NAME=dev DATASOURCES=prometheus,loki KEYCLOAK_URL=https://sso.example.com"; \
		echo ""; \
		echo "  Optional params: GRAFANA_URL, VAULT_ADDR, VAULT_MOUNT, VAULT_NAMESPACE, KEYCLOAK_URL, BACKEND, ORGS, DATASOURCES"; \
		echo ""; \
		exit 1; \
	fi
	@ENV_NAME_ARG="$(NAME)" \
	 GRAFANA_URL_ARG="$(GRAFANA_URL)" \
	 VAULT_ADDR_ARG="$(VAULT_ADDR)" \
	 VAULT_MOUNT_ARG="$(VAULT_MOUNT)" \
	 VAULT_NAMESPACE_ARG="$(VAULT_NAMESPACE)" \
	 KEYCLOAK_URL_ARG="$(KEYCLOAK_URL)" \
	 BACKEND_ARG="$(BACKEND)" \
	 ORGS_ARG="$(ORGS)" \
	 DATASOURCES_ARG="$(DATASOURCES)" \
	 python3 scripts/new_env.py "$(NAME)"

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
	@python3 scripts/delete_env.py "$(NAME)"

# List all configured environments
list-envs:
	@python3 scripts/list_envs.py

# Validate an environment is ready for deployment
# Usage: make check-env ENV=staging
check-env:
	@python3 scripts/check_env.py "$(ENV)"

# =============================================================================
# TERRAFORM WORKFLOW
# =============================================================================

init:
	@echo "Initializing Terraform for $(ENV)..."
	terraform -chdir=$(TF_DIR) init -backend-config=$(TF_BACKEND) -reconfigure

plan:
	@echo "Planning changes for $(ENV)..."
	terraform -chdir=$(TF_DIR) plan -var-file=$(TF_VAR_FILE) -out=tfplan-$(ENV)

apply:
	@echo "Applying changes for $(ENV)..."
	@if [ -f $(TF_DIR)/tfplan-$(ENV) ]; then \
		terraform -chdir=$(TF_DIR) apply tfplan-$(ENV); \
	else \
		terraform -chdir=$(TF_DIR) apply -var-file=$(TF_VAR_FILE); \
	fi

apply-auto:
	@echo "Auto-applying changes for $(ENV)..."
	terraform -chdir=$(TF_DIR) apply -var-file=$(TF_VAR_FILE) -auto-approve

destroy:
	@echo "WARNING: This will DESTROY all resources in $(ENV)!"
	@read -p "Type the environment name to confirm: " confirm && [ "$$confirm" = "$(ENV)" ]
	terraform -chdir=$(TF_DIR) destroy -var-file=$(TF_VAR_FILE)

# =============================================================================
# UTILITIES
# =============================================================================

fmt:
	@echo "Formatting Terraform files..."
	terraform fmt -recursive $(TF_DIR)

validate:
	@echo "Validating Terraform configuration..."
	terraform -chdir=$(TF_DIR) validate

clean:
	@echo "Cleaning Terraform cache..."
	rm -rf $(TF_DIR)/.terraform
	rm -f $(TF_DIR)/tfplan-*
	rm -f $(TF_DIR)/*.tfplan

lint:
	@echo "Running TFLint..."
	@cd $(TF_DIR) && tflint --init 2>/dev/null || true
	cd $(TF_DIR) && tflint --recursive
	@echo ""
	@echo "Running YAML lint..."
	@yamllint -d '{extends: default, rules: {line-length: {max: 200}, truthy: disable, document-start: disable}}' base/ envs/ 2>/dev/null || echo "(install yamllint: pip install yamllint)"
	@echo ""
	@echo "Running schema validation..."
	@python3 scripts/validate_config.py

validate-config:
	@python3 scripts/validate_config.py $(if $(ENV),--env $(ENV),)

# Install pre-commit hooks into the local git repo
pre-commit-install:
	@echo "Installing pre-commit hooks..."
	@pip install pre-commit yamale PyYAML --quiet 2>/dev/null || \
		pip install pre-commit yamale PyYAML --quiet --break-system-packages 2>/dev/null || \
		echo "Run: pip install pre-commit yamale PyYAML (or use a venv)"
	@pre-commit install
	@echo ""
	@echo "  Pre-commit hooks installed. They will run on every 'git commit'."
	@echo "  To run manually: make pre-commit-run"

# Run all pre-commit hooks against all files (useful for first-time check)
pre-commit-run:
	@pre-commit run --all-files

output:
	@echo "Terraform outputs for $(ENV):"
	terraform -chdir=$(TF_DIR) output

state-list:
	terraform -chdir=$(TF_DIR) state list

# =============================================================================
# OPERATIONS
# =============================================================================

drift:
	@python3 scripts/drift_detect.py "$(ENV)"

backup:
	@python3 scripts/backup.py "$(ENV)"

# Sync Keycloak groups → Grafana teams (OSS — no Enterprise needed)
# Usage: make team-sync ENV=prod GRAFANA_URL=http://localhost:3000 AUTH=admin:admin \
#        KEYCLOAK_URL=https://auth.example.com KEYCLOAK_USER=admin KEYCLOAK_PASS=secret
# Optional: KEYCLOAK_REALM=master (default) DRY_RUN=true
KEYCLOAK_URL   ?=
KEYCLOAK_REALM ?= master
KEYCLOAK_USER  ?=
KEYCLOAK_PASS  ?=
DRY_RUN        ?= false
team-sync:
	@if [ -z "$(GRAFANA_URL)" ] || [ -z "$(AUTH)" ] || [ -z "$(KEYCLOAK_URL)" ] || [ -z "$(KEYCLOAK_USER)" ] || [ -z "$(KEYCLOAK_PASS)" ]; then \
		echo ""; \
		echo "  Usage: make team-sync ENV=prod GRAFANA_URL=http://localhost:3000 AUTH=admin:admin \\"; \
		echo "         KEYCLOAK_URL=https://auth.example.com KEYCLOAK_USER=admin KEYCLOAK_PASS=secret"; \
		echo ""; \
		echo "  Optional: KEYCLOAK_REALM=master DRY_RUN=true"; \
		echo ""; \
		exit 1; \
	fi
	@GRAFANA_URL="$(GRAFANA_URL)" GRAFANA_AUTH="$(AUTH)" \
		KEYCLOAK_URL="$(KEYCLOAK_URL)" KEYCLOAK_REALM="$(KEYCLOAK_REALM)" \
		KEYCLOAK_USER="$(KEYCLOAK_USER)" KEYCLOAK_PASS="$(KEYCLOAK_PASS)" \
		DRY_RUN="$(DRY_RUN)" \
		python3 scripts/team_sync.py "envs/$(ENV)/teams.yaml"

# Import from existing Grafana instance
# Usage: make import ENV=prod GRAFANA_URL=https://grafana.example.com AUTH=admin:admin
#        make import ENV=prod GRAFANA_URL=... AUTH=... NO_TF_IMPORT=true
#        make import ENV=prod GRAFANA_URL=... AUTH=... NO_DASHBOARDS=true
AUTH          ?=
NO_TF_IMPORT  ?=
NO_DASHBOARDS ?=
import:
	@if [ -z "$(GRAFANA_URL)" ] || [ -z "$(AUTH)" ]; then \
		echo ""; \
		echo "  Usage: make import ENV=prod GRAFANA_URL=https://grafana.example.com AUTH=admin:admin"; \
		echo ""; \
		echo "  AUTH can be:"; \
		echo "    - Basic auth:  admin:password"; \
		echo "    - API token:   glsa_xxxxxxxxxx"; \
		echo ""; \
		echo "  Optional flags:"; \
		echo "    NO_TF_IMPORT=true   Skip Terraform state import (YAML only)"; \
		echo "    NO_DASHBOARDS=true  Skip dashboard JSON export"; \
		echo ""; \
		exit 1; \
	fi
	@python3 scripts/import_from_grafana.py "$(ENV)" \
		--grafana-url="$(GRAFANA_URL)" --auth="$(AUTH)" \
		$(if $(filter true,$(NO_TF_IMPORT)),--no-tf-import,) \
		$(if $(filter true,$(NO_DASHBOARDS)),--no-dashboards,)

# Promote configuration from one environment to another
# Usage: make promote FROM=staging TO=prod
FROM ?=
TO   ?=
promote:
	@if [ -z "$(FROM)" ] || [ -z "$(TO)" ]; then \
		echo ""; \
		echo "  Usage: make promote FROM=staging TO=prod"; \
		echo "         make promote FROM=staging TO=prod --diff-only"; \
		echo ""; \
		exit 1; \
	fi
	@python3 scripts/promote.py "$(FROM)" "$(TO)"

dashboard-diff:
	@python3 scripts/dashboard_diff.py "$(ENV)"

# Dry-run for new-env
dry-run:
	@if [ -z "$(NAME)" ]; then \
		echo "Usage: make dry-run NAME=staging"; \
		exit 1; \
	fi
	@python3 scripts/new_env.py "$(NAME)" --dry-run

# =============================================================================
# LOCAL DEVELOPMENT
# =============================================================================

dev-up:
	@echo "Starting Grafana + Vault + Keycloak..."
	docker compose up -d
	@echo ""
	@echo "  Grafana:   http://localhost:3000  (admin/admin)"
	@echo "  Vault:     http://localhost:8200  (token: root)"
	@echo "  Keycloak:  http://localhost:8080  (admin/admin)"
	@echo ""
	@echo "  Run 'make dev-bootstrap' to seed Vault and create a dev environment"

dev-down:
	@echo "Stopping local dev services..."
	docker compose down

dev-bootstrap:
	@python3 scripts/dev_bootstrap.py dev

test: dev-up dev-bootstrap
	@echo ""
	@echo "Running test cycle..."
	@export VAULT_TOKEN=root && \
		make init ENV=dev && \
		make plan ENV=dev && \
		echo "" && \
		echo "Test plan succeeded! Run 'make apply ENV=dev' to apply."

# =============================================================================
# VAULT OPERATIONS
# =============================================================================

vault-setup:
	@echo "Setting up Vault secrets for $(ENV)..."
	python3 scripts/vault/setup_secrets.py $(ENV)

vault-verify:
	@echo "Verifying Vault secrets for $(ENV)..."
	python3 scripts/vault/verify_secrets.py $(ENV)

# =============================================================================
# CI/CD TARGETS (non-interactive)
# =============================================================================

ci-init:
	terraform -chdir=$(TF_DIR) init -backend-config=$(TF_BACKEND) -input=false

ci-plan:
	terraform -chdir=$(TF_DIR) plan -var-file=$(TF_VAR_FILE) -input=false -out=tfplan

ci-apply:
	terraform -chdir=$(TF_DIR) apply -input=false -auto-approve tfplan

ci-destroy:
	terraform -chdir=$(TF_DIR) destroy -var-file=$(TF_VAR_FILE) -input=false -auto-approve
