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
        ci-init ci-plan ci-apply ci-destroy apply-auto \
        dev-up dev-down dev-bootstrap lint import drift backup promote \
        dashboard-diff test dry-run

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
	@echo "  lint          Run TFLint + YAML lint"
	@echo "  clean         Remove Terraform cache and plans"
	@echo "  output        Show Terraform outputs             ENV=staging"
	@echo "  state-list    List all resources in state"
	@echo ""
	@echo "  ─── Operations ───────────────────────────────────────────"
	@echo "  drift          Detect out-of-band changes        ENV=staging"
	@echo "  backup         Backup Grafana state via API      ENV=staging"
	@echo "  import         Import from existing Grafana      ENV=staging AUTH=admin:admin"
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
	 bash scripts/new-env.sh "$(NAME)"

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
	rm -f tfplan-*
	rm -f *.tfplan

lint:
	@echo "Running TFLint..."
	@tflint --init 2>/dev/null || true
	tflint --recursive
	@echo ""
	@echo "Running YAML lint..."
	@yamllint -d '{extends: default, rules: {line-length: {max: 200}, truthy: disable, document-start: disable}}' config/ 2>/dev/null || echo "(install yamllint: pip install yamllint)"

output:
	@echo "Terraform outputs for $(ENV):"
	terraform output

state-list:
	terraform state list

# =============================================================================
# OPERATIONS
# =============================================================================

drift:
	@bash scripts/drift-detect.sh "$(ENV)"

backup:
	@bash scripts/backup.sh "$(ENV)"

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
		bash scripts/team-sync.sh "config/$(ENV)/teams.yaml"

# Import from existing Grafana instance
# Usage: make import ENV=prod GRAFANA_URL=https://grafana.example.com AUTH=admin:admin
AUTH ?=
import:
	@if [ -z "$(GRAFANA_URL)" ] || [ -z "$(AUTH)" ]; then \
		echo ""; \
		echo "  Usage: make import ENV=prod GRAFANA_URL=https://grafana.example.com AUTH=admin:admin"; \
		echo ""; \
		echo "  AUTH can be:"; \
		echo "    - Basic auth:  admin:password"; \
		echo "    - API token:   glsa_xxxxxxxxxx"; \
		echo ""; \
		exit 1; \
	fi
	@bash scripts/import-from-grafana.sh "$(ENV)" --grafana-url="$(GRAFANA_URL)" --auth="$(AUTH)"

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
	@bash scripts/promote.sh "$(FROM)" "$(TO)"

dashboard-diff:
	@bash scripts/dashboard-diff.sh "$(ENV)"

# Dry-run for new-env
dry-run:
	@if [ -z "$(NAME)" ]; then \
		echo "Usage: make dry-run NAME=staging"; \
		exit 1; \
	fi
	@bash scripts/new-env.sh "$(NAME)" --dry-run

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
	@bash scripts/dev-bootstrap.sh dev

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
