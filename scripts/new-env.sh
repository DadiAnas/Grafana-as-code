#!/bin/bash
# =============================================================================
# CREATE NEW ENVIRONMENT — Scaffolding Script
# =============================================================================
# Creates all files needed for a new Grafana-as-Code environment:
#   - environments/<name>.tfvars
#   - backends/<name>.tfbackend
#   - config/<name>/ (all YAML config files)
#   - dashboards/<name>/<org>/ (for each org in shared/organizations.yaml)
#
# Usage:
#   bash scripts/new-env.sh <env-name> [grafana-url]
#
# Examples:
#   bash scripts/new-env.sh staging
#   bash scripts/new-env.sh production https://grafana.example.com
# =============================================================================

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# -------------------------------------------------------------------------
# Parse arguments
# -------------------------------------------------------------------------
ENV_NAME="${1:-}"
GRAFANA_URL="${2:-http://localhost:3000}"

if [ -z "$ENV_NAME" ]; then
    echo -e "${RED}Error: Environment name is required${NC}"
    echo ""
    echo "Usage: $0 <env-name> [grafana-url]"
    echo ""
    echo "Examples:"
    echo "  $0 staging"
    echo "  $0 production https://grafana.example.com"
    exit 1
fi

# Validate env name (alphanumeric, hyphens, underscores only)
if ! echo "$ENV_NAME" | grep -qE '^[a-zA-Z][a-zA-Z0-9_-]*$'; then
    echo -e "${RED}Error: Invalid environment name '${ENV_NAME}'${NC}"
    echo "Names must start with a letter and contain only letters, numbers, hyphens, and underscores."
    exit 1
fi

# Check if environment already exists
if [ -d "$PROJECT_ROOT/config/$ENV_NAME" ]; then
    echo -e "${RED}Error: Environment '${ENV_NAME}' already exists!${NC}"
    echo ""
    echo "Existing files:"
    [ -f "$PROJECT_ROOT/environments/$ENV_NAME.tfvars" ] && echo "  ✓ environments/$ENV_NAME.tfvars"
    [ -f "$PROJECT_ROOT/backends/$ENV_NAME.tfbackend" ] && echo "  ✓ backends/$ENV_NAME.tfbackend"
    [ -d "$PROJECT_ROOT/config/$ENV_NAME" ] && echo "  ✓ config/$ENV_NAME/"
    [ -d "$PROJECT_ROOT/dashboards/$ENV_NAME" ] && echo "  ✓ dashboards/$ENV_NAME/"
    echo ""
    echo "To recreate, first run: make delete-env NAME=$ENV_NAME"
    exit 1
fi

echo -e "${BOLD}${CYAN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║          Creating New Environment: ${ENV_NAME}"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

CREATED_FILES=()

# -------------------------------------------------------------------------
# 1. Create environments/<name>.tfvars
# -------------------------------------------------------------------------
echo -e "${BLUE}[1/4]${NC} Creating ${YELLOW}environments/${ENV_NAME}.tfvars${NC}"
cat > "$PROJECT_ROOT/environments/${ENV_NAME}.tfvars" << EOF
# =============================================================================
# ${ENV_NAME^^} ENVIRONMENT — Terraform Variables
# =============================================================================
# Usage:
#   terraform plan  -var-file=environments/${ENV_NAME}.tfvars
#   terraform apply -var-file=environments/${ENV_NAME}.tfvars
# =============================================================================

# The URL of your Grafana instance
grafana_url = "${GRAFANA_URL}"

# Environment name — must match directory names under config/ and dashboards/
environment = "${ENV_NAME}"

# Vault Configuration (HashiCorp Vault for secrets management)
vault_address = "http://localhost:8200"
vault_mount   = "grafana"
# vault_token — set via VAULT_TOKEN env variable for security:
#   export VAULT_TOKEN="your-vault-token"

# Keycloak Configuration (optional — only if you enable SSO via Keycloak)
# keycloak_url = "https://keycloak.example.com"
EOF
CREATED_FILES+=("environments/${ENV_NAME}.tfvars")

# -------------------------------------------------------------------------
# 2. Create backends/<name>.tfbackend
# -------------------------------------------------------------------------
echo -e "${BLUE}[2/4]${NC} Creating ${YELLOW}backends/${ENV_NAME}.tfbackend${NC}"
cat > "$PROJECT_ROOT/backends/${ENV_NAME}.tfbackend" << EOF
# =============================================================================
# BACKEND CONFIGURATION — ${ENV_NAME}
# =============================================================================
# Use with: terraform init -backend-config=backends/${ENV_NAME}.tfbackend
#
# Uncomment and configure one of the backends below.
# By default, Terraform uses local state (no backend needed).
# =============================================================================

# --- AWS S3 Backend ---
# bucket         = "my-terraform-state"
# key            = "${ENV_NAME}/grafana/terraform.tfstate"
# region         = "us-east-1"
# encrypt        = true
# dynamodb_table = "terraform-locks"

# --- Azure Blob Storage ---
# resource_group_name  = "my-rg"
# storage_account_name = "mytfstate"
# container_name       = "tfstate"
# key                  = "${ENV_NAME}/grafana/terraform.tfstate"

# --- Google Cloud Storage ---
# bucket = "my-terraform-state"
# prefix = "${ENV_NAME}/grafana"
EOF
CREATED_FILES+=("backends/${ENV_NAME}.tfbackend")

# -------------------------------------------------------------------------
# 3. Create config/<name>/ with all YAML files
# -------------------------------------------------------------------------
echo -e "${BLUE}[3/4]${NC} Creating ${YELLOW}config/${ENV_NAME}/${NC} configuration files"

mkdir -p "$PROJECT_ROOT/config/${ENV_NAME}/alerting"

# Organizations
cat > "$PROJECT_ROOT/config/${ENV_NAME}/organizations.yaml" << EOF
# ${ENV_NAME^^} — Organization overrides (override shared by name)
organizations: []
EOF

# Datasources
cat > "$PROJECT_ROOT/config/${ENV_NAME}/datasources.yaml" << EOF
# ${ENV_NAME^^} — Datasource overrides (override shared by UID)
# Example: different Prometheus URL for this environment
datasources: []
  # - name: "Prometheus"
  #   type: "prometheus"
  #   uid: "prometheus"
  #   url: "http://prometheus-${ENV_NAME}:9090"
  #   org: "Main Organization"
  #   is_default: true
EOF

# Folders
cat > "$PROJECT_ROOT/config/${ENV_NAME}/folders.yaml" << EOF
# ${ENV_NAME^^} — Folder permission overrides (override shared by UID)
folders: []
EOF

# Teams
cat > "$PROJECT_ROOT/config/${ENV_NAME}/teams.yaml" << EOF
# ${ENV_NAME^^} — Team overrides (override shared by name)
teams: []
EOF

# Service accounts
cat > "$PROJECT_ROOT/config/${ENV_NAME}/service_accounts.yaml" << EOF
# ${ENV_NAME^^} — Service account overrides (override shared by name)
service_accounts: []
EOF

# SSO
cat > "$PROJECT_ROOT/config/${ENV_NAME}/sso.yaml" << EOF
# ${ENV_NAME^^} — SSO overrides (merged with shared)
sso: {}
  # auth_url: "https://keycloak-${ENV_NAME}.example.com/realms/grafana/protocol/openid-connect/auth"
EOF

# Keycloak
cat > "$PROJECT_ROOT/config/${ENV_NAME}/keycloak.yaml" << EOF
# ${ENV_NAME^^} — Keycloak overrides (merged with shared)
keycloak: {}
EOF

# Alerting
cat > "$PROJECT_ROOT/config/${ENV_NAME}/alerting/alert_rules.yaml" << EOF
# ${ENV_NAME^^} — Alert rule overrides (override shared by folder-name)
groups: []
EOF

cat > "$PROJECT_ROOT/config/${ENV_NAME}/alerting/contact_points.yaml" << EOF
# ${ENV_NAME^^} — Contact point overrides (override shared by name)
contactPoints: []
EOF

cat > "$PROJECT_ROOT/config/${ENV_NAME}/alerting/notification_policies.yaml" << EOF
# ${ENV_NAME^^} — Notification policy overrides (override shared by org)
policies: []
EOF

CREATED_FILES+=("config/${ENV_NAME}/ (10 files)")

# -------------------------------------------------------------------------
# 4. Create dashboards/<name>/ with org directories
# -------------------------------------------------------------------------
echo -e "${BLUE}[4/4]${NC} Creating ${YELLOW}dashboards/${ENV_NAME}/${NC} directory structure"

# Parse org names from shared organizations.yaml
ORG_FILE="$PROJECT_ROOT/config/shared/organizations.yaml"
if [ -f "$ORG_FILE" ]; then
    # Extract organization names from YAML (handle quotes)
    ORG_NAMES=$(grep -E '^\s+- name:' "$ORG_FILE" | sed 's/.*name:\s*//;s/"//g;s/'"'"'//g;s/\s*$//' | grep -v '^#' || true)
else
    ORG_NAMES="Main Organization"
fi

if [ -z "$ORG_NAMES" ]; then
    ORG_NAMES="Main Organization"
fi

while IFS= read -r org; do
    org=$(echo "$org" | xargs)  # trim whitespace
    [ -z "$org" ] && continue
    mkdir -p "$PROJECT_ROOT/dashboards/${ENV_NAME}/${org}"
    touch "$PROJECT_ROOT/dashboards/${ENV_NAME}/${org}/.gitkeep"
    echo -e "       └── dashboards/${ENV_NAME}/${CYAN}${org}${NC}/"
done <<< "$ORG_NAMES"

CREATED_FILES+=("dashboards/${ENV_NAME}/")

# -------------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------------
echo ""
echo -e "${BOLD}${GREEN}✅ Environment '${ENV_NAME}' created successfully!${NC}"
echo ""
echo -e "${BOLD}Created files:${NC}"
for f in "${CREATED_FILES[@]}"; do
    echo -e "  ${GREEN}✓${NC} $f"
done

echo ""
echo -e "${BOLD}${YELLOW}Next steps:${NC}"
echo -e "  ${CYAN}1.${NC} Edit ${YELLOW}environments/${ENV_NAME}.tfvars${NC} with your Grafana URL"
echo -e "  ${CYAN}2.${NC} Edit ${YELLOW}config/shared/*.yaml${NC} or ${YELLOW}config/${ENV_NAME}/*.yaml${NC} with your config"
echo -e "  ${CYAN}3.${NC} Add dashboard JSON files to ${YELLOW}dashboards/${ENV_NAME}/ or dashboards/shared/${NC}"
echo -e "  ${CYAN}4.${NC} Set up Vault secrets:"
echo -e "     ${BOLD}make vault-setup ENV=${ENV_NAME}${NC}"
echo -e "  ${CYAN}5.${NC} Initialize & plan:"
echo -e "     ${BOLD}make init ENV=${ENV_NAME}${NC}"
echo -e "     ${BOLD}make plan ENV=${ENV_NAME}${NC}"
echo -e "  ${CYAN}6.${NC} Apply when ready:"
echo -e "     ${BOLD}make apply ENV=${ENV_NAME}${NC}"
echo ""
