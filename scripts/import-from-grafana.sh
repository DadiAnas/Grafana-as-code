#!/bin/bash
# =============================================================================
# IMPORT FROM GRAFANA — Generate YAML configs from an existing instance
# =============================================================================
# Connects to a running Grafana instance and generates YAML configuration
# files that can be used with this Terraform framework.
#
# Prerequisites:
#   - curl and jq installed
#   - Grafana API access (admin user or service account token)
#
# Usage:
#   bash scripts/import-from-grafana.sh <env-name> \
#     --grafana-url=https://grafana.example.com \
#     --auth=admin:admin
#
#   # Or with API token:
#   bash scripts/import-from-grafana.sh prod \
#     --grafana-url=https://grafana.example.com \
#     --auth=glsa_xxxxxxxxxxxx
#
# Via Make:
#   make import ENV=prod GRAFANA_URL=https://grafana.example.com AUTH=admin:admin
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# =========================================================================
# Arguments
# =========================================================================
ENV_NAME=""
GRAFANA_URL=""
AUTH=""
IMPORT_DASHBOARDS=true
OUTPUT_DIR=""

show_help() {
    echo ""
    echo "  Usage: $0 <env-name> [options]"
    echo ""
    echo "  Required:"
    echo "    <env-name>                     Target environment name"
    echo "    --grafana-url=<url>            Grafana instance URL"
    echo "    --auth=<credentials>           API token or user:password"
    echo ""
    echo "  Optional:"
    echo "    --no-dashboards                Skip dashboard export"
    echo "    --output-dir=<path>            Output directory (default: project root)"
    echo ""
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --grafana-url=*)   GRAFANA_URL="${1#*=}"; shift ;;
        --auth=*)          AUTH="${1#*=}"; shift ;;
        --no-dashboards)   IMPORT_DASHBOARDS=false; shift ;;
        --output-dir=*)    OUTPUT_DIR="${1#*=}"; shift ;;
        --help|-h)         show_help ;;
        -*)                echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
        *)                 [ -z "$ENV_NAME" ] && ENV_NAME="$1"; shift ;;
    esac
done

# Also accept env vars
[ -z "$ENV_NAME" ] && ENV_NAME="${ENV_NAME_ARG:-}"
[ -z "$GRAFANA_URL" ] && GRAFANA_URL="${GRAFANA_URL_ARG:-}"
[ -z "$AUTH" ] && AUTH="${AUTH_ARG:-}"

# Validation
if [ -z "$ENV_NAME" ] || [ -z "$GRAFANA_URL" ] || [ -z "$AUTH" ]; then
    echo -e "${RED}Error: env-name, --grafana-url, and --auth are required${NC}"
    echo "Use --help for usage."
    exit 1
fi

OUTPUT="${OUTPUT_DIR:-$PROJECT_ROOT}"

# Remove trailing slash from URL
GRAFANA_URL="${GRAFANA_URL%/}"

# Determine auth header
if [[ "$AUTH" == *":"* ]]; then
    AUTH_HEADER="-u ${AUTH}"
else
    AUTH_HEADER="-H 'Authorization: Bearer ${AUTH}'"
fi

# =========================================================================
# API Helper
# =========================================================================
grafana_api() {
    local endpoint="$1"
    if [[ "$AUTH" == *":"* ]]; then
        curl -sf -u "${AUTH}" "${GRAFANA_URL}${endpoint}" 2>/dev/null
    else
        curl -sf -H "Authorization: Bearer ${AUTH}" "${GRAFANA_URL}${endpoint}" 2>/dev/null
    fi
}

# Test connection
echo -e "${BOLD}${CYAN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║          Importing from Grafana → ${ENV_NAME}"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

HEALTH=$(grafana_api "/api/health" || echo "FAILED")
if echo "$HEALTH" | grep -q "ok"; then
    VERSION=$(echo "$HEALTH" | grep -oP '"version"\s*:\s*"\K[^"]+' 2>/dev/null || echo "unknown")
    echo -e "  ${GREEN}✓${NC} Connected to Grafana ${VERSION} at ${GRAFANA_URL}"
else
    echo -e "  ${RED}✗ Cannot connect to Grafana at ${GRAFANA_URL}${NC}"
    echo "  Check URL and credentials."
    exit 1
fi
echo ""

IMPORTED_COUNT=0

# =========================================================================
# 1. Organizations
# =========================================================================
echo -e "${BLUE}[1/7]${NC} Importing organizations..."

ORGS_JSON=$(grafana_api "/api/orgs" || echo "[]")
ORG_COUNT=$(echo "$ORGS_JSON" | (grep -c '"id"' || true))

CONFIG_DIR="${OUTPUT}/config/${ENV_NAME}"
mkdir -p "${CONFIG_DIR}/alerting"

if [ "$ORG_COUNT" -gt 0 ]; then
    {
        echo "# Imported from ${GRAFANA_URL} on $(date -Iseconds)"
        echo "# Organizations: ${ORG_COUNT}"
        echo ""
        echo "organizations:"
        echo "$ORGS_JSON" | python3 -c "
import json, sys
orgs = json.load(sys.stdin)
for org in orgs:
    print(f'  - name: \"{org[\"name\"]}\"')
    print(f'    id: {org[\"id\"]}')
    print(f'    admins: []')
    print(f'    editors: []')
    print(f'    viewers: []')
    print()
" 2>/dev/null || {
        # Fallback without python
        echo "$ORGS_JSON" | grep -o '"name":"[^"]*"' | while read -r match; do
            name=$(echo "$match" | cut -d'"' -f4)
            echo "  - name: \"${name}\""
            echo "    admins: []"
            echo "    editors: []"
            echo "    viewers: []"
            echo ""
        done
    }
    } > "${CONFIG_DIR}/organizations.yaml"
    echo -e "  ${GREEN}✓${NC} ${ORG_COUNT} organization(s) → config/${ENV_NAME}/organizations.yaml"
    IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
else
    echo -e "  ${DIM}  No organizations found (besides default)${NC}"
fi

# =========================================================================
# 2. Datasources
# =========================================================================
echo -e "${BLUE}[2/7]${NC} Importing datasources..."

DS_JSON=$(grafana_api "/api/datasources" || echo "[]")
DS_COUNT=$(echo "$DS_JSON" | (grep -c '"id"' || true))

if [ "$DS_COUNT" -gt 0 ]; then
    {
        echo "# Imported from ${GRAFANA_URL} on $(date -Iseconds)"
        echo "# Datasources: ${DS_COUNT}"
        echo ""
        echo "datasources:"
        echo "$DS_JSON" | python3 -c "
import json, sys
datasources = json.load(sys.stdin)
for ds in datasources:
    print(f'  - name: \"{ds[\"name\"]}\"')
    print(f'    uid: \"{ds.get(\"uid\", ds[\"name\"].lower().replace(\" \", \"-\"))}\"')
    print(f'    type: \"{ds[\"type\"]}\"')
    print(f'    url: \"{ds.get(\"url\", \"\")}\"')
    print(f'    org: \"{ds.get(\"orgId\", 1)}\"')
    access = ds.get('access', 'proxy')
    print(f'    access: \"{access}\"')
    is_default = str(ds.get('isDefault', False)).lower()
    print(f'    is_default: {is_default}')
    # JSON data
    json_data = ds.get('jsonData', {})
    if json_data:
        print(f'    json_data:')
        for k, v in json_data.items():
            if isinstance(v, bool):
                print(f'      {k}: {str(v).lower()}')
            elif isinstance(v, (int, float)):
                print(f'      {k}: {v}')
            else:
                print(f'      {k}: \"{v}\"')
    print()
" 2>/dev/null || echo "  # Failed to parse — check jq/python"
    } > "${CONFIG_DIR}/datasources.yaml"
    echo -e "  ${GREEN}✓${NC} ${DS_COUNT} datasource(s) → config/${ENV_NAME}/datasources.yaml"
    IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
else
    echo -e "  ${DIM}  No datasources found${NC}"
fi

# =========================================================================
# 3. Folders
# =========================================================================
echo -e "${BLUE}[3/7]${NC} Importing folders..."

FOLDERS_JSON=$(grafana_api "/api/folders?limit=1000" || echo "[]")
FOLDER_COUNT=$(echo "$FOLDERS_JSON" | (grep -c '"uid"' || true))

if [ "$FOLDER_COUNT" -gt 0 ]; then
    {
        echo "# Imported from ${GRAFANA_URL} on $(date -Iseconds)"
        echo "# Folders: ${FOLDER_COUNT}"
        echo ""
        echo "folders:"
        echo "$FOLDERS_JSON" | python3 -c "
import json, sys
folders = json.load(sys.stdin)
for f in folders:
    print(f'  - title: \"{f[\"title\"]}\"')
    print(f'    uid: \"{f[\"uid\"]}\"')
    if f.get('parentUid'):
        print(f'    parent_uid: \"{f[\"parentUid\"]}\"')
    print(f'    permissions: []')
    print()
" 2>/dev/null || echo "  # Failed to parse"
    } > "${CONFIG_DIR}/folders.yaml"
    echo -e "  ${GREEN}✓${NC} ${FOLDER_COUNT} folder(s) → config/${ENV_NAME}/folders.yaml"
    IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
else
    echo -e "  ${DIM}  No folders found${NC}"
fi

# =========================================================================
# 4. Teams
# =========================================================================
echo -e "${BLUE}[4/7]${NC} Importing teams..."

TEAMS_JSON=$(grafana_api "/api/teams/search?perpage=1000" || echo '{"teams":[]}')
TEAM_COUNT=$(echo "$TEAMS_JSON" | (grep -c '"id"' || true))

if [ "$TEAM_COUNT" -gt 0 ]; then
    {
        echo "# Imported from ${GRAFANA_URL} on $(date -Iseconds)"
        echo "# Teams: ${TEAM_COUNT}"
        echo ""
        echo "teams:"
        echo "$TEAMS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
teams = data.get('teams', [])
for t in teams:
    print(f'  - name: \"{t[\"name\"]}\"')
    if t.get('email'):
        print(f'    email: \"{t[\"email\"]}\"')
    print(f'    org: \"Main Organization\"')
    print(f'    members: []')
    print()
" 2>/dev/null || echo "  # Failed to parse"
    } > "${CONFIG_DIR}/teams.yaml"
    echo -e "  ${GREEN}✓${NC} ${TEAM_COUNT} team(s) → config/${ENV_NAME}/teams.yaml"
    IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
else
    echo -e "  ${DIM}  No teams found${NC}"
fi

# =========================================================================
# 5. Service Accounts
# =========================================================================
echo -e "${BLUE}[5/7]${NC} Importing service accounts..."

SA_JSON=$(grafana_api "/api/serviceaccounts/search?perpage=1000" || echo '{"serviceAccounts":[]}')
SA_COUNT=$(echo "$SA_JSON" | (grep -c '"id"' || true))

if [ "$SA_COUNT" -gt 0 ]; then
    {
        echo "# Imported from ${GRAFANA_URL} on $(date -Iseconds)"
        echo "# Service Accounts: ${SA_COUNT}"
        echo ""
        echo "service_accounts:"
        echo "$SA_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
sas = data.get('serviceAccounts', [])
for sa in sas:
    print(f'  - name: \"{sa[\"name\"]}\"')
    print(f'    role: \"{sa.get(\"role\", \"Viewer\")}\"')
    print(f'    is_disabled: {str(sa.get(\"isDisabled\", False)).lower()}')
    print(f'    org: \"Main Organization\"')
    print()
" 2>/dev/null || echo "  # Failed to parse"
    } > "${CONFIG_DIR}/service_accounts.yaml"
    echo -e "  ${GREEN}✓${NC} ${SA_COUNT} service account(s) → config/${ENV_NAME}/service_accounts.yaml"
    IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
else
    echo -e "  ${DIM}  No service accounts found${NC}"
fi

# =========================================================================
# 6. Alert Rules & Contact Points
# =========================================================================
echo -e "${BLUE}[6/7]${NC} Importing alerting configuration..."

# Contact points
CP_JSON=$(grafana_api "/api/v1/provisioning/contact-points" || echo "[]")
CP_COUNT=$(echo "$CP_JSON" | (grep -c '"uid"' || true))

if [ "$CP_COUNT" -gt 0 ]; then
    {
        echo "# Imported from ${GRAFANA_URL} on $(date -Iseconds)"
        echo "# Contact Points: ${CP_COUNT}"
        echo ""
        echo "contactPoints:"
        echo "$CP_JSON" | python3 -c "
import json, sys
cps = json.load(sys.stdin)
# Group by name
grouped = {}
for cp in cps:
    name = cp['name']
    if name not in grouped:
        grouped[name] = {'name': name, 'receivers': []}
    grouped[name]['receivers'].append({
        'type': cp['type'],
        'settings': cp.get('settings', {})
    })

for name, cp in grouped.items():
    print(f'  - name: \"{name}\"')
    print(f'    org: \"Main Organization\"')
    print(f'    receivers:')
    for r in cp['receivers']:
        print(f'      - type: \"{r[\"type\"]}\"')
        if r['settings']:
            print(f'        settings:')
            for k, v in r['settings'].items():
                if isinstance(v, bool):
                    print(f'          {k}: {str(v).lower()}')
                elif isinstance(v, str):
                    # Escape quotes
                    v_escaped = v.replace('\"', '\\\\\"')
                    print(f'          {k}: \"{v_escaped}\"')
                else:
                    print(f'          {k}: {v}')
    print()
" 2>/dev/null || echo "  # Failed to parse"
    } > "${CONFIG_DIR}/alerting/contact_points.yaml"
    echo -e "  ${GREEN}✓${NC} ${CP_COUNT} contact point(s) → config/${ENV_NAME}/alerting/contact_points.yaml"
    IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
fi

# Alert rules
AR_JSON=$(grafana_api "/api/v1/provisioning/alert-rules" || echo "[]")
AR_COUNT=$(echo "$AR_JSON" | (grep -c '"uid"' || true))

if [ "$AR_COUNT" -gt 0 ]; then
    {
        echo "# Imported from ${GRAFANA_URL} on $(date -Iseconds)"
        echo "# Alert Rules: ${AR_COUNT}"
        echo ""
        echo "groups:"
        echo "$AR_JSON" | python3 -c "
import json, sys
rules = json.load(sys.stdin)
# Group by folder + group name
groups = {}
for rule in rules:
    folder = rule.get('folderUID', 'general')
    group = rule.get('ruleGroup', 'default')
    key = f'{folder}/{group}'
    if key not in groups:
        groups[key] = {
            'name': group,
            'folder': folder,
            'interval': rule.get('execErrState', '1m'),
            'rules': []
        }
    groups[key]['rules'].append({
        'title': rule.get('title', ''),
        'condition': rule.get('condition', ''),
        'for': rule.get('for', '5m'),
    })

for key, g in groups.items():
    print(f'  - name: \"{g[\"name\"]}\"')
    print(f'    folder: \"{g[\"folder\"]}\"')
    print(f'    interval: \"1m\"')
    print(f'    rules:')
    for r in g['rules']:
        print(f'      - title: \"{r[\"title\"]}\"')
        print(f'        condition: \"{r[\"condition\"]}\"')
        print(f'        for: \"{r[\"for\"]}\"')
    print()
" 2>/dev/null || echo "  # Failed to parse"
    } > "${CONFIG_DIR}/alerting/alert_rules.yaml"
    echo -e "  ${GREEN}✓${NC} ${AR_COUNT} alert rule(s) → config/${ENV_NAME}/alerting/alert_rules.yaml"
    IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
fi

# Empty notification policies (need manual config)
cat > "${CONFIG_DIR}/alerting/notification_policies.yaml" << EOF
# Imported from ${GRAFANA_URL} on $(date -Iseconds)
# NOTE: Notification policies need manual configuration.
# Use: GET /api/v1/provisioning/policies to inspect current policies.

policies: []
EOF

# =========================================================================
# 7. Dashboards
# =========================================================================
if [ "$IMPORT_DASHBOARDS" = true ]; then
    echo -e "${BLUE}[7/7]${NC} Importing dashboards..."

    SEARCH_JSON=$(grafana_api "/api/search?type=dash-db&limit=5000" || echo "[]")
    DASH_COUNT=$(echo "$SEARCH_JSON" | (grep -c '"uid"' || true))

    if [ "$DASH_COUNT" -gt 0 ]; then
        # Get folder mapping
        DASH_DIR="${OUTPUT}/dashboards/${ENV_NAME}"
        EXPORTED=0

        echo "$SEARCH_JSON" | python3 -c "
import json, sys
dashboards = json.load(sys.stdin)
for d in dashboards:
    uid = d.get('uid', '')
    folder = d.get('folderTitle', 'General')
    title = d.get('title', 'unknown')
    # Print: uid|folder|title
    print(f'{uid}|{folder}|{title}')
" 2>/dev/null | while IFS='|' read -r uid folder title; do
            # Sanitize folder name
            safe_folder=$(echo "$folder" | sed 's/[^a-zA-Z0-9 _-]//g')
            [ -z "$safe_folder" ] && safe_folder="General"

            mkdir -p "${DASH_DIR}/${safe_folder}"

            # Export dashboard JSON
            DASH_JSON=$(grafana_api "/api/dashboards/uid/${uid}" || echo "")
            if [ -n "$DASH_JSON" ]; then
                # Extract just the dashboard object, remove id/version for clean import
                echo "$DASH_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
dash = data.get('dashboard', {})
dash.pop('id', None)
dash.pop('version', None)
print(json.dumps(dash, indent=2))
" 2>/dev/null > "${DASH_DIR}/${safe_folder}/${title}.json"
                EXPORTED=$((EXPORTED + 1))
                echo -e "  ${GREEN}✓${NC} ${folder}/${title}.json"
            fi
        done

        echo -e "  ${GREEN}✓${NC} Exported dashboards to dashboards/${ENV_NAME}/"
        IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
    else
        echo -e "  ${DIM}  No dashboards found${NC}"
    fi
else
    echo -e "${BLUE}[7/7]${NC} ${DIM}Skipping dashboards (--no-dashboards)${NC}"
fi

# =========================================================================
# Create placeholder files for configs we can't auto-import
# =========================================================================
[ ! -f "${CONFIG_DIR}/sso.yaml" ] && cat > "${CONFIG_DIR}/sso.yaml" << 'EOF'
# SSO configuration — must be configured manually
# Import cannot extract OAuth settings from Grafana API

sso:
  enabled: false
EOF

[ ! -f "${CONFIG_DIR}/keycloak.yaml" ] && cat > "${CONFIG_DIR}/keycloak.yaml" << 'EOF'
# Keycloak configuration — must be configured manually

keycloak:
  enabled: false
EOF

# =========================================================================
# Summary
# =========================================================================
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ Import complete!${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Source:      ${GRAFANA_URL}"
echo "  Target env:  ${ENV_NAME}"
echo "  Imported:    ${IMPORTED_COUNT} resource type(s)"
echo ""
echo "  Generated files:"
echo "    config/${ENV_NAME}/"
ls -1 "${CONFIG_DIR}/" 2>/dev/null | sed 's/^/      /'
echo "    config/${ENV_NAME}/alerting/"
ls -1 "${CONFIG_DIR}/alerting/" 2>/dev/null | sed 's/^/      /'
if [ "$IMPORT_DASHBOARDS" = true ]; then
    DASH_DIR="${OUTPUT}/dashboards/${ENV_NAME}"
    if [ -d "$DASH_DIR" ]; then
        DASH_FILE_COUNT=$(find "$DASH_DIR" -name "*.json" 2>/dev/null | wc -l)
        echo "    dashboards/${ENV_NAME}/ (${DASH_FILE_COUNT} dashboards)"
    fi
fi
echo ""
echo -e "  ${YELLOW}⚠  Review and adjust the generated YAML files before applying!${NC}"
echo "  Some values (SSO, secrets, Keycloak) need manual configuration."
echo ""
echo "  Next steps:"
echo "    1. Review config/${ENV_NAME}/*.yaml"
echo "    2. Create environments/${ENV_NAME}.tfvars (or run: make new-env NAME=${ENV_NAME})"
echo "    3. Set up Vault secrets: make vault-setup ENV=${ENV_NAME}"
echo "    4. Import existing state: terraform import ..."
echo ""
