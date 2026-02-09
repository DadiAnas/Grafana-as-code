#!/bin/bash
# =============================================================================
# CREATE NEW ENVIRONMENT — Scaffolding Script
# =============================================================================
# Creates all files needed for a new Grafana-as-Code environment.
#
# Required:
#   ENV_NAME            Environment name (first positional arg or --name)
#
# Optional:
#   GRAFANA_URL         Grafana instance URL               (default: http://localhost:3000)
#   VAULT_ADDR          Vault server address                (default: http://localhost:8200)
#   VAULT_MOUNT         Vault KV mount path                 (default: grafana)
#   KEYCLOAK_URL        Keycloak URL — enables SSO config   (default: empty/disabled)
#   BACKEND             Backend type: s3, azurerm, gcs      (default: all commented)
#   ORGS                Comma-separated organization names  (default: from shared config)
#   DATASOURCES         Comma-separated datasource presets  (default: none)
#                       Options: prometheus, loki, postgres, mysql, elasticsearch,
#                                influxdb, tempo, mimir, cloudwatch, graphite
#
# Usage via Make:
#   make new-env NAME=staging
#   make new-env NAME=prod GRAFANA_URL=https://grafana.example.com BACKEND=s3
#   make new-env NAME=dev DATASOURCES=prometheus,loki,postgres KEYCLOAK_URL=https://sso.example.com
#   make new-env NAME=test ORGS="Main Organization,Platform Team,BI"
#
# Usage directly:
#   bash scripts/new-env.sh staging
#   bash scripts/new-env.sh --name=prod --grafana-url=https://grafana.example.com --backend=s3
# =============================================================================

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# =========================================================================
# Defaults
# =========================================================================
ENV_NAME=""
GRAFANA_URL="http://localhost:3000"
VAULT_ADDR="http://localhost:8200"
VAULT_MOUNT="grafana"
KEYCLOAK_URL=""
BACKEND=""
ORGS=""
DATASOURCES=""

# =========================================================================
# Parse arguments — supports both positional and --flag=value styles
# =========================================================================
show_help() {
    echo ""
    echo "  Usage: $0 <env-name> [options]"
    echo ""
    echo "  Required:"
    echo "    <env-name>                     Environment name (positional or --name=...)"
    echo ""
    echo "  Optional:"
    echo "    --grafana-url=<url>            Grafana URL               (default: http://localhost:3000)"
    echo "    --vault-addr=<url>             Vault address             (default: http://localhost:8200)"
    echo "    --vault-mount=<path>           Vault KV mount            (default: grafana)"
    echo "    --keycloak-url=<url>           Keycloak URL (enables SSO)"
    echo "    --backend=<type>               Backend: s3, azurerm, gcs (default: all commented)"
    echo "    --orgs=<org1,org2,...>          Custom organization names (comma-separated)"
    echo "    --datasources=<ds1,ds2,...>     Datasource presets (comma-separated)"
    echo "                                   Options: prometheus, loki, postgres, mysql,"
    echo "                                   elasticsearch, influxdb, tempo, mimir, cloudwatch, graphite"
    echo ""
    echo "  Examples:"
    echo "    $0 staging"
    echo "    $0 prod --grafana-url=https://grafana.example.com --backend=s3"
    echo "    $0 dev --datasources=prometheus,loki,postgres --keycloak-url=https://sso.example.com"
    echo "    $0 test --orgs='Main Organization,Platform Team,BI'"
    echo ""
    echo "  Via Make:"
    echo "    make new-env NAME=staging"
    echo "    make new-env NAME=prod GRAFANA_URL=https://grafana.example.com BACKEND=s3"
    echo "    make new-env NAME=dev DATASOURCES=prometheus,loki KEYCLOAK_URL=https://sso.example.com"
    echo ""
    exit 0
}

POSITIONAL_SET=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --name=*)          ENV_NAME="${1#*=}"; shift ;;
        --grafana-url=*)   GRAFANA_URL="${1#*=}"; shift ;;
        --vault-addr=*)    VAULT_ADDR="${1#*=}"; shift ;;
        --vault-mount=*)   VAULT_MOUNT="${1#*=}"; shift ;;
        --keycloak-url=*)  KEYCLOAK_URL="${1#*=}"; shift ;;
        --backend=*)       BACKEND="${1#*=}"; shift ;;
        --orgs=*)          ORGS="${1#*=}"; shift ;;
        --datasources=*)   DATASOURCES="${1#*=}"; shift ;;
        --help|-h)         show_help ;;
        -*)                echo -e "${RED}Unknown option: $1${NC}"; echo "Use --help for usage."; exit 1 ;;
        *)
            # Positional args: 1st=name, 2nd=grafana_url (backward compat)
            if [ "$POSITIONAL_SET" = false ]; then
                ENV_NAME="$1"
                POSITIONAL_SET=true
            elif [ "$GRAFANA_URL" = "http://localhost:3000" ]; then
                GRAFANA_URL="$1"
            fi
            shift
            ;;
    esac
done

# Also accept env vars from Makefile
[ -z "$ENV_NAME" ] && ENV_NAME="${ENV_NAME_ARG:-}"
[ "$GRAFANA_URL" = "http://localhost:3000" ] && [ -n "${GRAFANA_URL_ARG:-}" ] && GRAFANA_URL="$GRAFANA_URL_ARG"
[ "$VAULT_ADDR" = "http://localhost:8200" ] && [ -n "${VAULT_ADDR_ARG:-}" ] && VAULT_ADDR="$VAULT_ADDR_ARG"
[ "$VAULT_MOUNT" = "grafana" ] && [ -n "${VAULT_MOUNT_ARG:-}" ] && VAULT_MOUNT="$VAULT_MOUNT_ARG"
[ -z "$KEYCLOAK_URL" ] && [ -n "${KEYCLOAK_URL_ARG:-}" ] && KEYCLOAK_URL="$KEYCLOAK_URL_ARG"
[ -z "$BACKEND" ] && [ -n "${BACKEND_ARG:-}" ] && BACKEND="$BACKEND_ARG"
[ -z "$ORGS" ] && [ -n "${ORGS_ARG:-}" ] && ORGS="$ORGS_ARG"
[ -z "$DATASOURCES" ] && [ -n "${DATASOURCES_ARG:-}" ] && DATASOURCES="$DATASOURCES_ARG"

# =========================================================================
# Validation
# =========================================================================
if [ -z "$ENV_NAME" ]; then
    echo -e "${RED}Error: Environment name is required${NC}"
    echo ""
    echo "  Usage: $0 <env-name> [options]"
    echo "  Use --help for all options."
    exit 1
fi

if ! echo "$ENV_NAME" | grep -qE '^[a-zA-Z][a-zA-Z0-9_-]*$'; then
    echo -e "${RED}Error: Invalid environment name '${ENV_NAME}'${NC}"
    echo "Names must start with a letter and contain only letters, numbers, hyphens, and underscores."
    exit 1
fi

if [ -n "$BACKEND" ] && ! echo "$BACKEND" | grep -qE '^(s3|azurerm|gcs)$'; then
    echo -e "${RED}Error: Invalid backend type '${BACKEND}'${NC}"
    echo "Supported: s3, azurerm, gcs"
    exit 1
fi

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

# =========================================================================
# Header
# =========================================================================
echo -e "${BOLD}${CYAN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║          Creating New Environment: ${ENV_NAME}"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "  ${DIM}Grafana URL:   ${GRAFANA_URL}${NC}"
echo -e "  ${DIM}Vault:         ${VAULT_ADDR} (mount: ${VAULT_MOUNT})${NC}"
[ -n "$KEYCLOAK_URL" ] && echo -e "  ${DIM}Keycloak:      ${KEYCLOAK_URL}${NC}"
[ -n "$BACKEND" ] && echo -e "  ${DIM}Backend:       ${BACKEND}${NC}"
[ -n "$ORGS" ] && echo -e "  ${DIM}Organizations: ${ORGS}${NC}"
[ -n "$DATASOURCES" ] && echo -e "  ${DIM}Datasources:   ${DATASOURCES}${NC}"
echo ""

CREATED_FILES=()

# =========================================================================
# 1. environments/<name>.tfvars
# =========================================================================
echo -e "${BLUE}[1/4]${NC} Creating ${YELLOW}environments/${ENV_NAME}.tfvars${NC}"

KEYCLOAK_LINE="# keycloak_url = \"https://keycloak.example.com\""
if [ -n "$KEYCLOAK_URL" ]; then
    KEYCLOAK_LINE="keycloak_url = \"${KEYCLOAK_URL}\""
fi

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
vault_address = "${VAULT_ADDR}"
vault_mount   = "${VAULT_MOUNT}"
# vault_token — set via VAULT_TOKEN env variable for security:
#   export VAULT_TOKEN="your-vault-token"

# Keycloak Configuration (optional — only if you enable SSO via Keycloak)
${KEYCLOAK_LINE}
EOF
CREATED_FILES+=("environments/${ENV_NAME}.tfvars")

# =========================================================================
# 2. backends/<name>.tfbackend
# =========================================================================
echo -e "${BLUE}[2/4]${NC} Creating ${YELLOW}backends/${ENV_NAME}.tfbackend${NC}"

# Generate backend content based on BACKEND type
generate_backend() {
    echo "# ============================================================================="
    echo "# BACKEND CONFIGURATION — ${ENV_NAME}"
    echo "# ============================================================================="
    echo "# Use with: terraform init -backend-config=backends/${ENV_NAME}.tfbackend"
    echo "# ============================================================================="
    echo ""

    local s3_comment="#" azure_comment="#" gcs_comment="#"
    case "${BACKEND}" in
        s3)      s3_comment="" ;;
        azurerm) azure_comment="" ;;
        gcs)     gcs_comment="" ;;
    esac

    echo "# --- AWS S3 Backend ---"
    echo "${s3_comment} bucket         = \"my-terraform-state\""
    echo "${s3_comment} key            = \"${ENV_NAME}/grafana/terraform.tfstate\""
    echo "${s3_comment} region         = \"us-east-1\""
    echo "${s3_comment} encrypt        = true"
    echo "${s3_comment} dynamodb_table = \"terraform-locks\""
    echo ""
    echo "# --- Azure Blob Storage ---"
    echo "${azure_comment} resource_group_name  = \"my-rg\""
    echo "${azure_comment} storage_account_name = \"mytfstate\""
    echo "${azure_comment} container_name       = \"tfstate\""
    echo "${azure_comment} key                  = \"${ENV_NAME}/grafana/terraform.tfstate\""
    echo ""
    echo "# --- Google Cloud Storage ---"
    echo "${gcs_comment} bucket = \"my-terraform-state\""
    echo "${gcs_comment} prefix = \"${ENV_NAME}/grafana\""
}

generate_backend > "$PROJECT_ROOT/backends/${ENV_NAME}.tfbackend"
CREATED_FILES+=("backends/${ENV_NAME}.tfbackend")

# =========================================================================
# 3. config/<name>/ with all YAML files
# =========================================================================
echo -e "${BLUE}[3/4]${NC} Creating ${YELLOW}config/${ENV_NAME}/${NC} configuration files"

mkdir -p "$PROJECT_ROOT/config/${ENV_NAME}/alerting"

# --- Organizations ---
cat > "$PROJECT_ROOT/config/${ENV_NAME}/organizations.yaml" << EOF
# ${ENV_NAME^^} — Organization overrides (override shared by name)
organizations: []
EOF

# --- Datasources ---
generate_datasources() {
    echo "# ${ENV_NAME^^} — Datasource overrides (override shared by UID)"

    if [ -z "$DATASOURCES" ]; then
        echo "# Example: different Prometheus URL for this environment"
        echo "datasources: []"
        echo "  # - name: \"Prometheus\""
        echo "  #   type: \"prometheus\""
        echo "  #   uid: \"prometheus\""
        echo "  #   url: \"http://prometheus-${ENV_NAME}:9090\""
        echo "  #   org: \"Main Organization\""
        echo "  #   is_default: true"
        return
    fi

    echo "datasources:"
    local first=true

    IFS=',' read -ra DS_LIST <<< "$DATASOURCES"
    for ds in "${DS_LIST[@]}"; do
        ds=$(echo "$ds" | xargs)  # trim
        [ -z "$ds" ] && continue

        local is_default="false"
        if [ "$first" = true ]; then
            is_default="true"
            first=false
        fi

        case "$ds" in
            prometheus)
                cat << DSEOF
  - name: "Prometheus"
    type: "prometheus"
    uid: "prometheus"
    url: "http://prometheus-${ENV_NAME}:9090"
    org: "Main Organization"
    is_default: ${is_default}
    json_data:
      httpMethod: "POST"
      timeInterval: "15s"
DSEOF
                ;;
            loki)
                cat << DSEOF
  - name: "Loki"
    type: "loki"
    uid: "loki"
    url: "http://loki-${ENV_NAME}:3100"
    org: "Main Organization"
    json_data:
      maxLines: 1000
DSEOF
                ;;
            postgres|postgresql)
                cat << DSEOF
  - name: "PostgreSQL"
    type: "postgres"
    uid: "postgres"
    url: "postgres-${ENV_NAME}.example.com:5432"
    org: "Main Organization"
    use_vault: true
    json_data:
      database: "grafana_${ENV_NAME}"
      sslmode: "require"
      maxOpenConns: 10
DSEOF
                ;;
            mysql)
                cat << DSEOF
  - name: "MySQL"
    type: "mysql"
    uid: "mysql"
    url: "mysql-${ENV_NAME}.example.com:3306"
    org: "Main Organization"
    use_vault: true
    json_data:
      database: "grafana_${ENV_NAME}"
      maxOpenConns: 10
DSEOF
                ;;
            elasticsearch|elastic)
                cat << DSEOF
  - name: "Elasticsearch"
    type: "elasticsearch"
    uid: "elasticsearch"
    url: "http://elasticsearch-${ENV_NAME}:9200"
    org: "Main Organization"
    json_data:
      esVersion: "8.0.0"
      timeField: "@timestamp"
      logMessageField: "message"
      logLevelField: "level"
DSEOF
                ;;
            influxdb|influx)
                cat << DSEOF
  - name: "InfluxDB"
    type: "influxdb"
    uid: "influxdb"
    url: "http://influxdb-${ENV_NAME}:8086"
    org: "Main Organization"
    use_vault: true
    json_data:
      version: "Flux"
      organization: "my-org"
      defaultBucket: "my-bucket"
DSEOF
                ;;
            tempo)
                cat << DSEOF
  - name: "Tempo"
    type: "tempo"
    uid: "tempo"
    url: "http://tempo-${ENV_NAME}:3200"
    org: "Main Organization"
    json_data:
      tracesToLogsV2:
        datasourceUid: "loki"
      tracesToMetrics:
        datasourceUid: "prometheus"
DSEOF
                ;;
            mimir)
                cat << DSEOF
  - name: "Mimir"
    type: "prometheus"
    uid: "mimir"
    url: "http://mimir-${ENV_NAME}:9009/prometheus"
    org: "Main Organization"
    json_data:
      httpMethod: "POST"
DSEOF
                ;;
            cloudwatch)
                cat << DSEOF
  - name: "CloudWatch"
    type: "cloudwatch"
    uid: "cloudwatch"
    org: "Main Organization"
    json_data:
      defaultRegion: "us-east-1"
      authType: "default"
DSEOF
                ;;
            graphite)
                cat << DSEOF
  - name: "Graphite"
    type: "graphite"
    uid: "graphite"
    url: "http://graphite-${ENV_NAME}:8080"
    org: "Main Organization"
    json_data:
      graphiteVersion: "1.1"
DSEOF
                ;;
            *)
                echo "  # Unknown datasource type: ${ds} — add manually"
                ;;
        esac
    done
}

generate_datasources > "$PROJECT_ROOT/config/${ENV_NAME}/datasources.yaml"

# --- Folders ---
cat > "$PROJECT_ROOT/config/${ENV_NAME}/folders.yaml" << EOF
# ${ENV_NAME^^} — Folder permission overrides (override shared by UID)
folders: []
EOF

# --- Teams ---
cat > "$PROJECT_ROOT/config/${ENV_NAME}/teams.yaml" << EOF
# ${ENV_NAME^^} — Team overrides (override shared by name)
teams: []
EOF

# --- Service accounts ---
cat > "$PROJECT_ROOT/config/${ENV_NAME}/service_accounts.yaml" << EOF
# ${ENV_NAME^^} — Service account overrides (override shared by name)
service_accounts: []
EOF

# --- SSO ---
generate_sso() {
    echo "# ${ENV_NAME^^} — SSO overrides (merged with shared)"
    if [ -n "$KEYCLOAK_URL" ]; then
        cat << SSOEOF
sso:
  enabled: true
  auth_url: "${KEYCLOAK_URL}/realms/grafana/protocol/openid-connect/auth"
  token_url: "${KEYCLOAK_URL}/realms/grafana/protocol/openid-connect/token"
  api_url: "${KEYCLOAK_URL}/realms/grafana/protocol/openid-connect/userinfo"
  # client_id: "grafana-${ENV_NAME}"
  # use_vault: true  # client_secret from Vault at: ${VAULT_MOUNT}/${ENV_NAME}/sso/keycloak
SSOEOF
    else
        cat << SSOEOF
sso: {}
  # auth_url: "https://keycloak-${ENV_NAME}.example.com/realms/grafana/protocol/openid-connect/auth"
SSOEOF
    fi
}
generate_sso > "$PROJECT_ROOT/config/${ENV_NAME}/sso.yaml"

# --- Keycloak ---
generate_keycloak() {
    echo "# ${ENV_NAME^^} — Keycloak overrides (merged with shared)"
    if [ -n "$KEYCLOAK_URL" ]; then
        cat << KCEOF
keycloak:
  enabled: true
  url: "${KEYCLOAK_URL}"
  realm: "grafana"
  # client_id: "grafana-${ENV_NAME}"
KCEOF
    else
        echo "keycloak: {}"
    fi
}
generate_keycloak > "$PROJECT_ROOT/config/${ENV_NAME}/keycloak.yaml"

# --- Alerting ---
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

# =========================================================================
# 4. dashboards/<name>/ with org directories
# =========================================================================
echo -e "${BLUE}[4/4]${NC} Creating ${YELLOW}dashboards/${ENV_NAME}/${NC} directory structure"

# Determine organization names
ORG_NAMES=""
if [ -n "$ORGS" ]; then
    # User-provided orgs (comma-separated)
    ORG_NAMES=$(echo "$ORGS" | tr ',' '\n')
else
    # Parse from shared organizations.yaml
    ORG_FILE="$PROJECT_ROOT/config/shared/organizations.yaml"
    if [ -f "$ORG_FILE" ]; then
        ORG_NAMES=$(grep -E '^\s+- name:' "$ORG_FILE" | sed 's/.*name:\s*//;s/"//g;s/'"'"'//g;s/\s*$//' | grep -v '^#' || true)
    fi
fi

# Fallback
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

# =========================================================================
# Summary
# =========================================================================
echo ""
echo -e "${BOLD}${GREEN}✅ Environment '${ENV_NAME}' created successfully!${NC}"
echo ""
echo -e "${BOLD}Created files:${NC}"
for f in "${CREATED_FILES[@]}"; do
    echo -e "  ${GREEN}✓${NC} $f"
done

echo ""
echo -e "${BOLD}Configuration:${NC}"
echo -e "  Grafana URL:   ${BOLD}${GRAFANA_URL}${NC}"
echo -e "  Vault:         ${BOLD}${VAULT_ADDR}${NC} (mount: ${VAULT_MOUNT})"
[ -n "$KEYCLOAK_URL" ] && echo -e "  Keycloak:      ${BOLD}${KEYCLOAK_URL}${NC} ${GREEN}(SSO enabled)${NC}"
[ -n "$BACKEND" ] && echo -e "  Backend:       ${BOLD}${BACKEND}${NC} ${GREEN}(pre-configured)${NC}"
[ -n "$DATASOURCES" ] && echo -e "  Datasources:   ${BOLD}${DATASOURCES}${NC} ${GREEN}(pre-configured)${NC}"

echo ""
echo -e "${BOLD}${YELLOW}Next steps:${NC}"

STEP=1
if [ -z "$KEYCLOAK_URL" ] && [ -z "$DATASOURCES" ]; then
    echo -e "  ${CYAN}${STEP}.${NC} Edit ${YELLOW}environments/${ENV_NAME}.tfvars${NC} and ${YELLOW}config/${ENV_NAME}/*.yaml${NC} with your config"
    STEP=$((STEP + 1))
fi

echo -e "  ${CYAN}${STEP}.${NC} Add dashboard JSON files to ${YELLOW}dashboards/${ENV_NAME}/${NC} or ${YELLOW}dashboards/shared/${NC}"
STEP=$((STEP + 1))

echo -e "  ${CYAN}${STEP}.${NC} Set up Vault secrets:"
echo -e "     ${BOLD}make vault-setup ENV=${ENV_NAME}${NC}"
STEP=$((STEP + 1))

echo -e "  ${CYAN}${STEP}.${NC} Validate, initialize & deploy:"
echo -e "     ${BOLD}make check-env ENV=${ENV_NAME}${NC}"
echo -e "     ${BOLD}make init ENV=${ENV_NAME}${NC}"
echo -e "     ${BOLD}make plan ENV=${ENV_NAME}${NC}"
echo -e "     ${BOLD}make apply ENV=${ENV_NAME}${NC}"
echo ""
