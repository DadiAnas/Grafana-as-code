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
VAULT_NAMESPACE=""
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
    echo "    --vault-namespace=<ns>         Vault Enterprise namespace (e.g., admin/grafana)"
    echo "    --keycloak-url=<url>           Keycloak URL (enables SSO)"
    echo "    --backend=<type>               Backend: s3, azurerm, gcs, gitlab (default: all commented)"
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
        --vault-namespace=*) VAULT_NAMESPACE="${1#*=}"; shift ;;
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
[ -z "$VAULT_NAMESPACE" ] && [ -n "${VAULT_NAMESPACE_ARG:-}" ] && VAULT_NAMESPACE="$VAULT_NAMESPACE_ARG"
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

if [ -n "$BACKEND" ] && ! echo "$BACKEND" | grep -qE '^(s3|azurerm|gcs|gitlab)$'; then
    echo -e "${RED}Error: Invalid backend type '${BACKEND}'${NC}"
    echo "Supported: s3, azurerm, gcs, gitlab"
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
VAULT_DISPLAY="${VAULT_ADDR} (mount: ${VAULT_MOUNT})"
[ -n "$VAULT_NAMESPACE" ] && VAULT_DISPLAY="${VAULT_DISPLAY} [ns: ${VAULT_NAMESPACE}]"
echo -e "  ${DIM}Vault:         ${VAULT_DISPLAY}${NC}"
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

VAULT_NS_LINE="# vault_namespace = \"admin/grafana\"   # e.g., admin/team-x"
if [ -n "$VAULT_NAMESPACE" ]; then
    VAULT_NS_LINE="vault_namespace = \"${VAULT_NAMESPACE}\""
fi

cat > "$PROJECT_ROOT/environments/${ENV_NAME}.tfvars" << EOF
# =============================================================================
# ${ENV_NAME^^} ENVIRONMENT — Terraform Variables
# =============================================================================
# This file contains all Terraform variables for the '${ENV_NAME}' environment.
#
# Usage:
#   make plan  ENV=${ENV_NAME}
#   make apply ENV=${ENV_NAME}
#
# Or directly:
#   terraform plan  -var-file=environments/${ENV_NAME}.tfvars
#   terraform apply -var-file=environments/${ENV_NAME}.tfvars
# =============================================================================

# ─── Grafana Connection ─────────────────────────────────────────────────
# The full URL of your Grafana instance (including protocol and port)
grafana_url = "${GRAFANA_URL}"

# Environment name — used to locate config/ and dashboards/ subdirectories
# Must match: config/${ENV_NAME}/ and dashboards/${ENV_NAME}/
environment = "${ENV_NAME}"

# ─── Vault Configuration ────────────────────────────────────────────────
# HashiCorp Vault for secrets management (datasource passwords, SSO secrets)
vault_address = "${VAULT_ADDR}"
vault_mount   = "${VAULT_MOUNT}"

# Vault Enterprise namespace (leave commented for OSS Vault or root namespace)
# See: https://developer.hashicorp.com/vault/docs/enterprise/namespaces
${VAULT_NS_LINE}

# The vault token should be set via environment variable for security:
#   export VAULT_TOKEN="your-vault-token"
#
# To set up secrets in Vault:
#   make vault-setup ENV=${ENV_NAME}

# ─── Keycloak (Optional) ────────────────────────────────────────────────
# Only needed if you enable SSO via Keycloak (see config/${ENV_NAME}/sso.yaml)
${KEYCLOAK_LINE}

# ─── Additional Variables ────────────────────────────────────────────────
# Uncomment and set any additional variables your Terraform config needs:
#
# # Grafana authentication (alternative to Vault-stored API key)
# # grafana_auth = "admin:admin"          # Only for local dev!
#
# # Terraform state locking timeout
# # lock_timeout = "5m"
#
# # Enable/disable specific resource categories
# # manage_dashboards      = true
# # manage_datasources     = true
# # manage_alerting        = true
# # manage_service_accounts = true
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
    echo "# Remote state backends store terraform.tfstate on a shared backend"
    echo "# instead of the local filesystem, enabling team collaboration."
    echo "#"
    echo "# Usage:"
    echo "#   make init ENV=${ENV_NAME}"
    echo "# Or:"
    echo "#   terraform init -backend-config=backends/${ENV_NAME}.tfbackend"
    echo "#"
    echo "# Uncomment ONE backend section below (or use BACKEND= when creating the env)."
    echo "# For local-only state, you can leave everything commented."
    echo "# ============================================================================="
    echo ""

    local s3_comment="#" azure_comment="#" gcs_comment="#" gitlab_comment="#"
    case "${BACKEND}" in
        s3)      s3_comment="" ;;
        azurerm) azure_comment="" ;;
        gcs)     gcs_comment="" ;;
        gitlab)  gitlab_comment="" ;;
    esac

    echo "# --- AWS S3 Backend ---"
    echo "# Prerequisites: S3 bucket + DynamoDB table for state locking"
    echo "# See: https://developer.hashicorp.com/terraform/language/backend/s3"
    echo "${s3_comment} bucket         = \"my-terraform-state\""
    echo "${s3_comment} key            = \"${ENV_NAME}/grafana/terraform.tfstate\""
    echo "${s3_comment} region         = \"us-east-1\""
    echo "${s3_comment} encrypt        = true"
    echo "${s3_comment} dynamodb_table = \"terraform-locks\""
    echo ""
    echo "# --- Azure Blob Storage ---"
    echo "# Prerequisites: Storage account + container"
    echo "# See: https://developer.hashicorp.com/terraform/language/backend/azurerm"
    echo "${azure_comment} resource_group_name  = \"my-rg\""
    echo "${azure_comment} storage_account_name = \"mytfstate\""
    echo "${azure_comment} container_name       = \"tfstate\""
    echo "${azure_comment} key                  = \"${ENV_NAME}/grafana/terraform.tfstate\""
    echo ""
    echo "# --- Google Cloud Storage ---"
    echo "# Prerequisites: GCS bucket with versioning enabled"
    echo "# See: https://developer.hashicorp.com/terraform/language/backend/gcs"
    echo "${gcs_comment} bucket = \"my-terraform-state\""
    echo "${gcs_comment} prefix = \"${ENV_NAME}/grafana\""
    echo ""
    echo "# --- GitLab HTTP Backend ---"
    echo "# Prerequisites: GitLab project with Terraform state enabled"
    echo "# Auth: set TF_HTTP_USERNAME and TF_HTTP_PASSWORD env vars"
    echo "#   export TF_HTTP_USERNAME=\"gitlab-ci-token\"  # or your username"
    echo "#   export TF_HTTP_PASSWORD=\"\${CI_JOB_TOKEN}\"   # or a personal access token"
    echo "# See: https://docs.gitlab.com/ee/user/infrastructure/iac/terraform_state.html"
    echo "${gitlab_comment} address        = \"https://gitlab.example.com/api/v4/projects/<PROJECT_ID>/terraform/state/${ENV_NAME}\""
    echo "${gitlab_comment} lock_address   = \"https://gitlab.example.com/api/v4/projects/<PROJECT_ID>/terraform/state/${ENV_NAME}/lock\""
    echo "${gitlab_comment} unlock_address = \"https://gitlab.example.com/api/v4/projects/<PROJECT_ID>/terraform/state/${ENV_NAME}/lock\""
    echo "${gitlab_comment} lock_method    = \"POST\""
    echo "${gitlab_comment} unlock_method  = \"DELETE\""
    echo "${gitlab_comment} retry_wait_min = 5"
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
# =============================================================================
# ${ENV_NAME^^} — Organization Overrides
# =============================================================================
# Override shared organization settings for THIS environment only.
# Matching is by organization "name" — shared entries with the same name
# are replaced by entries here.
#
# Tip: Organizations are usually identical across environments.
#      Only add overrides here if ${ENV_NAME} needs different admins/editors.
# =============================================================================

organizations: []

  # --- Example: Override org admins for this environment ---
  # - name: "Main Organization"
  #   id: 1
  #   admins:
  #     - "admin-${ENV_NAME}@example.com"
  #   editors:
  #     - "dev-${ENV_NAME}@example.com"
  #   viewers: []
  #
  # --- Example: Add an env-specific organization ---
  # - name: "${ENV_NAME^} QA Team"
  #   admins:
  #     - "qa-lead@example.com"
EOF

# --- Datasources ---
generate_datasources() {
    cat << HEADER
# =============================================================================
# ${ENV_NAME^^} — Datasource Overrides
# =============================================================================
# Override shared datasource settings for THIS environment only.
# Matching is by datasource "uid" — shared entries with the same UID
# are replaced by entries here.
#
# Common use case: same datasource type, different URL per environment.
#
# For secrets (passwords, tokens), set use_vault: true and store credentials
# in Vault at: ${VAULT_MOUNT}/${ENV_NAME}/datasources/<datasource-name>
# =============================================================================

HEADER

    if [ -z "$DATASOURCES" ]; then
        cat << DSEOF
datasources: []

  # --- Example: Override Prometheus URL for this environment ---
  # - name: "Prometheus"
  #   type: "prometheus"
  #   uid: "prometheus"                    # Must match the shared UID to override
  #   url: "http://prometheus-${ENV_NAME}:9090"
  #   org: "Main Organization"
  #   is_default: true
  #   access_mode: "proxy"
  #   json_data:
  #     httpMethod: "POST"
  #     timeInterval: "15s"
  #
  # --- Example: Loki with environment-specific URL ---
  # - name: "Loki"
  #   type: "loki"
  #   uid: "loki"
  #   url: "http://loki-${ENV_NAME}:3100"
  #   org: "Main Organization"
  #   json_data:
  #     maxLines: 1000
  #
  # --- Example: PostgreSQL with Vault credentials ---
  # - name: "PostgreSQL"
  #   type: "grafana-postgresql-datasource"
  #   uid: "postgres"
  #   url: "postgres-${ENV_NAME}.example.com:5432"
  #   org: "Main Organization"
  #   use_vault: true                      # Reads from: ${VAULT_MOUNT}/${ENV_NAME}/datasources/PostgreSQL
  #   json_data:
  #     database: "grafana_${ENV_NAME}"
  #     sslmode: "require"
  #     maxOpenConns: 10
  #
  # --- Example: Elasticsearch ---
  # - name: "Elasticsearch"
  #   type: "elasticsearch"
  #   uid: "elasticsearch"
  #   url: "http://elasticsearch-${ENV_NAME}:9200"
  #   org: "Main Organization"
  #   json_data:
  #     esVersion: "8.0.0"
  #     timeField: "@timestamp"
  #     logMessageField: "message"
  #     logLevelField: "level"
DSEOF
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
# =============================================================================
# ${ENV_NAME^^} — Folder Permission Overrides
# =============================================================================
# Folders are auto-discovered from the dashboards/ directory structure:
#   dashboards/${ENV_NAME}/<org_name>/<folder_uid>/
#   dashboards/shared/<org_name>/<folder_uid>/
#
# This file is ONLY for setting permissions on those folders.
# If a folder is not listed here, it gets default (org-level) permissions.
# =============================================================================

folders: []

  # --- Example: Restrict folder access to specific teams ---
  # - uid: "infrastructure"               # Must match the directory name
  #   name: "Infrastructure Monitoring"    # Display name in Grafana
  #   org: "Main Organization"
  #   permissions:
  #     - team: "SRE Team"
  #       permission: "Admin"              # Admin | Edit | View
  #     - team: "Backend Team"
  #       permission: "Edit"
  #     - role: "Viewer"                   # Built-in role
  #       permission: "View"
  #
  # --- Example: Editor-accessible folder ---
  # - uid: "applications"
  #   name: "Application Dashboards"
  #   org: "Main Organization"
  #   permissions:
  #     - role: "Editor"
  #       permission: "Edit"
  #     - role: "Viewer"
  #       permission: "View"
EOF

# --- Teams ---
cat > "$PROJECT_ROOT/config/${ENV_NAME}/teams.yaml" << EOF
# =============================================================================
# ${ENV_NAME^^} — Team Overrides
# =============================================================================
# Override shared team settings for THIS environment only.
# Matching is by team "name" — shared entries with the same name
# are replaced by entries here.
#
# Teams are organization-scoped. Each team must specify "org".
# Teams can be assigned folder permissions (see folders.yaml).
# =============================================================================

teams: []

  # --- Example: Override team members for this environment ---
  # - name: "Backend Team"
  #   org: "Main Organization"
  #   email: "backend-${ENV_NAME}@example.com"
  #   members:
  #     - "dev1@example.com"
  #     - "dev2@example.com"
  #   preferences:
  #     theme: "dark"
  #     # home_dashboard_uid: "my-dashboard"
  #
  # --- Example: Environment-specific team ---
  # - name: "${ENV_NAME^} On-Call"
  #   org: "Main Organization"
  #   email: "oncall-${ENV_NAME}@example.com"
  #   preferences:
  #     theme: "dark"
EOF

# --- Service accounts ---
cat > "$PROJECT_ROOT/config/${ENV_NAME}/service_accounts.yaml" << EOF
# =============================================================================
# ${ENV_NAME^^} — Service Account Overrides
# =============================================================================
# Override shared service account settings for THIS environment only.
# Matching is by account "name" — shared entries with the same name
# are replaced by entries here.
#
# Service accounts provide programmatic access to Grafana via API tokens.
# Tokens are auto-generated and stored in Terraform state (sensitive).
# =============================================================================

service_accounts: []

  # --- Example: Automation service account for this environment ---
  # - name: "terraform-${ENV_NAME}"
  #   org: "Main Organization"
  #   role: "Admin"                        # Admin | Editor | Viewer
  #   is_disabled: false
  #   tokens:
  #     - name: "main-token"
  #       seconds_to_live: 0               # 0 = never expires
  #
  # --- Example: Read-only CI/CD account ---
  # - name: "ci-cd-readonly"
  #   org: "Main Organization"
  #   role: "Viewer"
  #   tokens:
  #     - name: "pipeline-token"
  #       seconds_to_live: 31536000        # 1 year in seconds
EOF

# --- SSO ---
generate_sso() {
    cat << HEADER
# =============================================================================
# ${ENV_NAME^^} — SSO Configuration Overrides
# =============================================================================
# Override shared SSO settings for THIS environment only.
# Values here are merged with config/shared/sso.yaml.
#
# Supported providers: Keycloak, Okta, Azure AD, Google, GitHub
# Client secrets are fetched from Vault at: ${VAULT_MOUNT}/${ENV_NAME}/sso/keycloak
#
# Key features:
#   - allowed_groups: restrict login to specific IdP groups
#   - groups[].org_mappings: map IdP groups to Grafana orgs + roles
#   - team sync: sync IdP groups to Grafana teams
# =============================================================================

HEADER
    if [ -n "$KEYCLOAK_URL" ]; then
        cat << SSOEOF
sso:
  enabled: true
  name: "Keycloak"

  # ─── OAuth2 Endpoints ───────────────────────────────────────────────
  auth_url: "${KEYCLOAK_URL}/realms/grafana/protocol/openid-connect/auth"
  token_url: "${KEYCLOAK_URL}/realms/grafana/protocol/openid-connect/token"
  api_url: "${KEYCLOAK_URL}/realms/grafana/protocol/openid-connect/userinfo"

  # ─── Client Configuration ──────────────────────────────────────────
  # client_id: "grafana-${ENV_NAME}"
  # use_vault: true                        # client_secret from Vault

  # ─── OAuth Settings ────────────────────────────────────────────────
  allow_sign_up: true
  auto_login: false
  scopes: "openid profile email groups"
  use_pkce: true
  use_refresh_token: true

  # ─── Access Control: Allowed Groups ────────────────────────────────
  # Restrict login to ONLY users in these IdP groups (comma-separated).
  # Users NOT in any of these groups will be denied access entirely.
  # Leave empty or remove to allow all authenticated users.
  # allowed_groups: "grafana-admins,grafana-editors,grafana-viewers"

  # ─── Role Mapping ─────────────────────────────────────────────────
  # skip_org_role_sync: false              # true = roles come ONLY from groups below
  # allow_assign_grafana_admin: true       # Allow granting server-wide admin via groups

  # ─── Sign Out ──────────────────────────────────────────────────────
  # signout_redirect_url: "${KEYCLOAK_URL}/realms/grafana/protocol/openid-connect/logout"

  # ─── Team Sync ─────────────────────────────────────────────────────
  # Sync IdP groups to Grafana teams automatically
  # teams_url: "${KEYCLOAK_URL}/realms/grafana/protocol/openid-connect/userinfo"
  # team_ids_attribute_path: "groups[*]"

  # ─── Group to Org Role Mappings ────────────────────────────────────
  # Maps IdP groups to Grafana organizations with specific roles.
  # Users ONLY get access to orgs explicitly listed in their group's org_mappings.
  #
  # Roles: Admin, Editor, Viewer (for org access)
  # Special: if a group has Admin on all orgs + allow_assign_grafana_admin: true,
  #          members get server-wide super admin rights.
  #
  # groups:
  #   - name: "grafana-admins"
  #     org_mappings:
  #       - org: "Main Organization"
  #         role: "Admin"
  #       - org: "Platform Team"
  #         role: "Admin"
  #
  #   - name: "grafana-editors"
  #     org_mappings:
  #       - org: "Main Organization"
  #         role: "Editor"
  #
  #   - name: "grafana-viewers"
  #     org_mappings:
  #       - org: "Main Organization"
  #         role: "Viewer"
SSOEOF
    else
        cat << SSOEOF
sso: {}

  # --- Example: Keycloak SSO for this environment ---
  # enabled: true
  # name: "Keycloak"
  #
  # # OAuth2 endpoints
  # auth_url: "https://keycloak-${ENV_NAME}.example.com/realms/grafana/protocol/openid-connect/auth"
  # token_url: "https://keycloak-${ENV_NAME}.example.com/realms/grafana/protocol/openid-connect/token"
  # api_url: "https://keycloak-${ENV_NAME}.example.com/realms/grafana/protocol/openid-connect/userinfo"
  # client_id: "grafana-${ENV_NAME}"
  # use_vault: true                        # Reads from: ${VAULT_MOUNT}/${ENV_NAME}/sso/keycloak
  #
  # # OAuth settings
  # allow_sign_up: true
  # auto_login: false
  # scopes: "openid profile email groups"
  # use_pkce: true
  # use_refresh_token: true
  #
  # # Restrict login to specific IdP groups (comma-separated)
  # # Users NOT in any of these groups will be denied access entirely
  # allowed_groups: "grafana-admins,grafana-editors,grafana-viewers"
  #
  # # Role mapping
  # skip_org_role_sync: false              # true = roles come ONLY from groups below
  # allow_assign_grafana_admin: true       # Allow granting server-wide admin
  #
  # # Sign out redirect (back to IdP logout)
  # signout_redirect_url: "https://keycloak-${ENV_NAME}.example.com/realms/grafana/protocol/openid-connect/logout"
  #
  # # Team sync — sync IdP groups to Grafana teams
  # teams_url: "https://keycloak-${ENV_NAME}.example.com/realms/grafana/protocol/openid-connect/userinfo"
  # team_ids_attribute_path: "groups[*]"
  #
  # # Map IdP groups → Grafana orgs + roles
  # # Users ONLY get access to orgs listed in their group's mappings
  # groups:
  #   - name: "grafana-admins"
  #     org_mappings:
  #       - org: "Main Organization"
  #         role: "Admin"
  #       - org: "Platform Team"
  #         role: "Admin"
  #
  #   - name: "grafana-editors"
  #     org_mappings:
  #       - org: "Main Organization"
  #         role: "Editor"
  #
  #   - name: "grafana-viewers"
  #     org_mappings:
  #       - org: "Main Organization"
  #         role: "Viewer"
  #
  # --- Example: Azure AD SSO ---
  # enabled: true
  # name: "Azure AD"
  # auth_url: "https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/authorize"
  # token_url: "https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token"
  # client_id: "grafana-${ENV_NAME}"
  # use_vault: true
  # scopes: "openid profile email"
SSOEOF
    fi
}
generate_sso > "$PROJECT_ROOT/config/${ENV_NAME}/sso.yaml"

# --- Keycloak ---
generate_keycloak() {
    cat << HEADER
# =============================================================================
# ${ENV_NAME^^} — Keycloak Client Management (Optional)
# =============================================================================
# Set enabled: true to let Terraform manage a Keycloak OAuth client
# for Grafana. This is SEPARATE from SSO — SSO can use any provider,
# while this manages the Keycloak client configuration itself.
#
# Credentials from Vault at: ${VAULT_MOUNT}/${ENV_NAME}/keycloak/provider-auth
# =============================================================================

HEADER
    if [ -n "$KEYCLOAK_URL" ]; then
        cat << KCEOF
keycloak:
  enabled: true
  url: "${KEYCLOAK_URL}"
  realm: "grafana"
  # client_id: "grafana-${ENV_NAME}"
  # client_name: "Grafana ${ENV_NAME^} (Terraform Managed)"
  # description: "Grafana OAuth Client for ${ENV_NAME}"
  #
  # --- OAuth Settings ---
  # access_type: "CONFIDENTIAL"           # CONFIDENTIAL | PUBLIC
  # standard_flow_enabled: true
  # valid_redirect_uris:
  #   - "https://grafana-${ENV_NAME}.example.com/login/generic_oauth"
  # web_origins:
  #   - "https://grafana-${ENV_NAME}.example.com"
KCEOF
    else
        cat << KCEOF
keycloak: {}

  # --- Example: Manage Keycloak client via Terraform ---
  # enabled: true
  # url: "https://keycloak.example.com"
  # realm: "grafana"
  # client_id: "grafana-${ENV_NAME}"
  # client_name: "Grafana ${ENV_NAME^}"
  #
  # access_type: "CONFIDENTIAL"
  # standard_flow_enabled: true
  # valid_redirect_uris:
  #   - "https://grafana-${ENV_NAME}.example.com/login/generic_oauth"
  # web_origins:
  #   - "https://grafana-${ENV_NAME}.example.com"
KCEOF
    fi
}
generate_keycloak > "$PROJECT_ROOT/config/${ENV_NAME}/keycloak.yaml"

# --- Alerting: Alert Rules ---
cat > "$PROJECT_ROOT/config/${ENV_NAME}/alerting/alert_rules.yaml" << EOF
# =============================================================================
# ${ENV_NAME^^} — Alert Rule Overrides
# =============================================================================
# Override shared alert rules for THIS environment only.
# Matching is by folder + rule group name.
#
# Each group must specify:
#   - folder: the folder UID (must match a directory in dashboards/)
#   - name: rule group name
#   - interval: evaluation interval (e.g., "1m", "5m")
#   - org: which organization this alert belongs to
#   - rules: list of alert rules
# =============================================================================

groups: []

  # --- Example: Environment-specific alert thresholds ---
  # - folder: "alerts"                    # Must exist in dashboards/${ENV_NAME}/
  #   name: "High CPU Usage"
  #   interval: "1m"
  #   org: "Main Organization"
  #   rules:
  #     - title: "CPU Usage Critical"
  #       condition: "C"
  #       for: "5m"
  #       annotations:
  #         summary: "CPU usage is above 90% on ${ENV_NAME}"
  #         description: "Instance {{ \$labels.instance }} has CPU > 90%"
  #       labels:
  #         severity: "critical"
  #         environment: "${ENV_NAME}"
  #       noDataState: "NoData"           # NoData | Alerting | OK
  #       execErrState: "Error"           # Error | Alerting | OK
  #       data:
  #         - refId: "A"
  #           datasourceUid: "prometheus"
  #           model:
  #             expr: "100 - (avg by(instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)"
  #         - refId: "C"
  #           datasourceUid: "-100"       # __expr__ (expression)
  #           model:
  #             type: "threshold"
  #             conditions:
  #               - evaluator:
  #                   type: "gt"
  #                   params: [90]         # Alert when > 90%
EOF

# --- Alerting: Contact Points ---
cat > "$PROJECT_ROOT/config/${ENV_NAME}/alerting/contact_points.yaml" << EOF
# =============================================================================
# ${ENV_NAME^^} — Contact Point Overrides
# =============================================================================
# Override shared contact points for THIS environment only.
# Matching is by contact point "name".
#
# Supported receiver types: email, webhook, slack, pagerduty, opsgenie,
#   discord, telegram, teams, googlechat, victorops, pushover, sns,
#   sensugo, threema, webex, line, kafka, oncall, alertmanager
# =============================================================================

contactPoints: []

  # --- Example: Email alerts for this environment ---
  # - name: "${ENV_NAME}-email-alerts"
  #   org: "Main Organization"
  #   receivers:
  #     - type: "email"
  #       settings:
  #         addresses: "oncall-${ENV_NAME}@example.com;team@example.com"
  #         singleEmail: false
  #
  # --- Example: Slack channel per environment ---
  # - name: "${ENV_NAME}-slack"
  #   org: "Main Organization"
  #   receivers:
  #     - type: "slack"
  #       settings:
  #         url: "https://hooks.slack.com/services/xxx/yyy/zzz"
  #         recipient: "#alerts-${ENV_NAME}"
  #         username: "Grafana ${ENV_NAME^}"
  #         icon_emoji: ":grafana:"
  #         title: '{{ template "slack.default.title" . }}'
  #         text: '{{ template "slack.default.text" . }}'
  #
  # --- Example: PagerDuty ---
  # - name: "${ENV_NAME}-pagerduty"
  #   org: "Main Organization"
  #   receivers:
  #     - type: "pagerduty"
  #       settings:
  #         integrationKey: "your-pagerduty-key"  # Store in Vault for security
  #         severity: "critical"
  #         class: "grafana"
  #
  # --- Example: Webhook (generic HTTP endpoint) ---
  # - name: "${ENV_NAME}-webhook"
  #   org: "Main Organization"
  #   receivers:
  #     - type: "webhook"
  #       settings:
  #         url: "https://alerts-${ENV_NAME}.example.com/webhook"
  #         httpMethod: "POST"
  #         username: "grafana"
  #         # password from Vault: use_vault: true
EOF

# --- Alerting: Notification Policies ---
cat > "$PROJECT_ROOT/config/${ENV_NAME}/alerting/notification_policies.yaml" << EOF
# =============================================================================
# ${ENV_NAME^^} — Notification Policy Overrides
# =============================================================================
# Override shared notification policies for THIS environment only.
# Matching is by organization.
#
# Policies define HOW alerts are routed to contact points:
#   - receiver: the default contact point
#   - group_by: labels to group alerts by
#   - routes: child policies with label matchers
# =============================================================================

policies: []

  # --- Example: Route alerts by severity ---
  # - org: "Main Organization"
  #   receiver: "${ENV_NAME}-email-alerts"     # Default contact point
  #   group_by:
  #     - "alertname"
  #     - "namespace"
  #   group_wait: "30s"
  #   group_interval: "5m"
  #   repeat_interval: "4h"
  #   routes:
  #     # Critical alerts → PagerDuty
  #     - receiver: "${ENV_NAME}-pagerduty"
  #       matchers:
  #         - "severity = critical"
  #       continue: false
  #       group_wait: "10s"                    # Alert faster for critical
  #
  #     # Warning alerts → Slack
  #     - receiver: "${ENV_NAME}-slack"
  #       matchers:
  #         - "severity = warning"
  #       continue: true                       # Also send to default receiver
  #       repeat_interval: "1h"
  #
  #     # Mute notifications for specific labels
  #     # - receiver: "${ENV_NAME}-email-alerts"
  #     #   matchers:
  #     #     - "alertname = Watchdog"
  #     #   mute_time_intervals:
  #     #     - "weekends"
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
