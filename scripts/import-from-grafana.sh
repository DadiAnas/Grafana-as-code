#!/bin/bash
# =============================================================================
# IMPORT FROM GRAFANA — Generate YAML configs from an existing instance
# =============================================================================
# Connects to a running Grafana instance and generates YAML configuration
# files that can be used with this Terraform framework.
#
# Prerequisites:
#   - curl and jq (or python3) installed
#   - Grafana API access (admin user or service account token)
#
# Usage:
#   bash scripts/import-from-grafana.sh <env-name> \
#     --grafana-url=https://grafana.example.com \
#     --auth=admin:admin
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
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

if [ -z "$ENV_NAME" ] || [ -z "$GRAFANA_URL" ] || [ -z "$AUTH" ]; then
    echo -e "${RED}Error: env-name, --grafana-url, and --auth are required${NC}"
    exit 1
fi

OUTPUT="${OUTPUT_DIR:-$PROJECT_ROOT}"
GRAFANA_URL="${GRAFANA_URL%/}"

# Global context variable
CURRENT_ORG_ID=""

# =========================================================================
# API Helper
# =========================================================================
grafana_api() {
    local endpoint="$1"
    local opts=("-sf")

    # Add Auth
    if [[ "$AUTH" == *":"* ]]; then
        opts+=("-u" "${AUTH}")
    else
        opts+=("-H" "Authorization: Bearer ${AUTH}")
    fi

    # Add Org Context if set
    if [ -n "${CURRENT_ORG_ID:-}" ]; then
        opts+=("-H" "X-Grafana-Org-Id: ${CURRENT_ORG_ID}")
    fi

    curl "${opts[@]}" "${GRAFANA_URL}${endpoint}" 2>/dev/null
}

# Test connection
echo -e "${BOLD}${CYAN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║          Importing from Grafana → ${ENV_NAME}"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

HEALTH=$(grafana_api "/api/health" || echo "FAILED")
if echo "$HEALTH" | grep -q "ok"; then
    # Fix: grep regex handling for JSON with spaces
    VERSION=$(echo "$HEALTH" | grep -oP '"version"\s*:\s*"\K[^"]+' 2>/dev/null || echo "unknown")
    echo -e "  ${GREEN}✓${NC} Connected to Grafana ${VERSION} at ${GRAFANA_URL}"
else
    echo -e "  ${RED}✗ Cannot connect to Grafana at ${GRAFANA_URL}${NC}"
    exit 1
fi
echo ""

IMPORTED_COUNT=0
CONFIG_DIR="${OUTPUT}/config/${ENV_NAME}"
mkdir -p "${CONFIG_DIR}/alerting"

# =========================================================================
# 1. Organizations
# =========================================================================
echo -e "${BLUE}[1/7]${NC} Importing organizations..."

ORGS_JSON=$(grafana_api "/api/orgs" || echo "[]")
# Fix: grep -c || true to avoid pipefail exit
ORG_COUNT=$(echo "$ORGS_JSON" | (grep -o '"id"' || true) | wc -l)

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
" 2>/dev/null
    } > "${CONFIG_DIR}/organizations.yaml"
    echo -e "  ${GREEN}✓${NC} ${ORG_COUNT} organization(s) → config/${ENV_NAME}/organizations.yaml"
    IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
else
    echo -e "  ${DIM}  No organizations found${NC}"
fi

# =========================================================================
# 2. Datasources
# =========================================================================
echo -e "${BLUE}[2/7]${NC} Importing datasources..."

DS_JSON=$(grafana_api "/api/datasources" || echo "[]")
DS_COUNT=$(echo "$DS_JSON" | (grep -o '"id"' || true) | wc -l)

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
    print(f'    access: \"{ds.get(\"access\", \"proxy\")}\"')
    print(f'    is_default: {str(ds.get(\"isDefault\", False)).lower()}')
    if ds.get('jsonData'):
        print(f'    json_data:')
        for k, v in ds['jsonData'].items():
            if isinstance(v, bool): print(f'      {k}: {str(v).lower()}')
            elif isinstance(v, (int, float)): print(f'      {k}: {v}')
            else: print(f'      {k}: \"{v}\"')
    print()
" 2>/dev/null
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
FOLDER_COUNT=$(echo "$FOLDERS_JSON" | (grep -o '"uid"' || true) | wc -l)

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
    print(f'    permissions: []')
    print()
" 2>/dev/null
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
TEAM_COUNT=$(echo "$TEAMS_JSON" | (grep -o '"id"' || true) | wc -l)

if [ "$TEAM_COUNT" -gt 0 ]; then
    {
        echo "# Imported from ${GRAFANA_URL} on $(date -Iseconds)"
        echo "teams:"
        echo "$TEAMS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for t in data.get('teams', []):
    print(f'  - name: \"{t[\"name\"]}\"')
    if t.get('email'): print(f'    email: \"{t[\"email\"]}\"')
    print(f'    org: \"Main Organization\"') # ToDo: Dynamic org mapping
    print(f'    members: []')
    print()
" 2>/dev/null
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
SA_COUNT=$(echo "$SA_JSON" | (grep -o '"id"' || true) | wc -l)

if [ "$SA_COUNT" -gt 0 ]; then
    {
        echo "# Imported from ${GRAFANA_URL} on $(date -Iseconds)"
        echo "service_accounts:"
        echo "$SA_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for sa in data.get('serviceAccounts', []):
    print(f'  - name: \"{sa[\"name\"]}\"')
    print(f'    role: \"{sa.get(\"role\", \"Viewer\")}\"')
    print(f'    is_disabled: {str(sa.get(\"isDisabled\", False)).lower()}')
    print(f'    org: \"Main Organization\"')
    print()
" 2>/dev/null
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

CP_JSON=$(grafana_api "/api/v1/provisioning/contact-points" || echo "[]")
CP_COUNT=$(echo "$CP_JSON" | (grep -o '"uid"' || true) | wc -l)

if [ "$CP_COUNT" -gt 0 ]; then
    {
        echo "contactPoints:"
        echo "$CP_JSON" | python3 -c "
import json, sys
cps = json.load(sys.stdin)
# Group by name to merge receivers
grouped = {}
for cp in cps:
    name = cp['name']
    if name not in grouped: grouped[name] = {'name': name, 'receivers': []}
    grouped[name]['receivers'].append({'type': cp['type'], 'settings': cp.get('settings', {})})

for name, cp in grouped.items():
    print(f'  - name: \"{name}\"')
    print(f'    org: \"Main Organization\"')
    print(f'    receivers:')
    for r in cp['receivers']:
        print(f'      - type: \"{r[\"type\"]}\"')
        if r['settings']:
            print(f'        settings:')
            for k, v in r['settings'].items():
                if isinstance(v, str): print(f'          {k}: \"{v}\"')
                else: print(f'          {k}: {v}')
    print()
" 2>/dev/null
    } > "${CONFIG_DIR}/alerting/contact_points.yaml"
    echo -e "  ${GREEN}✓${NC} ${CP_COUNT} contact point(s) imported"
    IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
fi

AR_JSON=$(grafana_api "/api/v1/provisioning/alert-rules" || echo "[]")
AR_COUNT=$(echo "$AR_JSON" | (grep -o '"uid"' || true) | wc -l)

if [ "$AR_COUNT" -gt 0 ]; then
    {
        echo "groups:"
        echo "$AR_JSON" | python3 -c "
import json, sys
rules = json.load(sys.stdin)
groups = {}
for rule in rules:
    folder = rule.get('folderUID', 'general')
    group = rule.get('ruleGroup', 'default')
    key = f'{folder}/{group}'
    if key not in groups:
        groups[key] = {'name': group, 'folder': folder, 'rules': []}
    groups[key]['rules'].append(rule)

for key, g in groups.items():
    print(f'  - name: \"{g[\"name\"]}\"')
    print(f'    folder: \"{g[\"folder\"]}\"')
    print(f'    interval: \"1m\"')
    print(f'    rules:')
    for r in g['rules']:
        print(f'      - title: \"{r.get(\"title\", \"\")}\"')
        print(f'        condition: \"{r.get(\"condition\", \"\")}\"')
        print(f'        for: \"{r.get(\"for\", \"5m\")}\"')
    print()
" 2>/dev/null
    } > "${CONFIG_DIR}/alerting/alert_rules.yaml"
    echo -e "  ${GREEN}✓${NC} ${AR_COUNT} alert rule(s) imported"
    IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
fi

# Placeholder for Policies
cat > "${CONFIG_DIR}/alerting/notification_policies.yaml" << EOF
# Imported from ${GRAFANA_URL}
policies: []
EOF

# =========================================================================
# 7. Dashboards (Loop over ALL Orgs)
# =========================================================================
if [ "$IMPORT_DASHBOARDS" = true ]; then
    echo -e "${BLUE}[7/7]${NC} Importing dashboards (scanning all organizations)..."

    DASH_DIR="${OUTPUT}/dashboards/${ENV_NAME}"
    TOTAL_EXPORTED=0

    # 1. Get List of Orgs to iterate
    ORG_LIST_RAW=$(echo "$ORGS_JSON" | python3 -c "
import json, sys
try:
    for o in json.load(sys.stdin):
        print(f'{o[\"id\"]}|{o[\"name\"]}')
except: pass
" 2>/dev/null || true)

    # 2. Loop Orgs
    while IFS='|' read -r THIS_ORG_ID THIS_ORG_NAME; do
        [ -z "$THIS_ORG_ID" ] && continue
        
        # Switch Context
        export CURRENT_ORG_ID="$THIS_ORG_ID"
        # echo -e "  • Scanning Org: ${THIS_ORG_NAME}..."

        SEARCH_JSON=$(grafana_api "/api/search?type=dash-db&limit=5000" || echo "[]")
        DASH_COUNT=$(echo "$SEARCH_JSON" | (grep -o '"uid"' || true) | wc -l)

        if [ "$DASH_COUNT" -gt 0 ]; then
            # Parse & Export
            echo "$SEARCH_JSON" | python3 -c "
import json, sys
dashboards = json.load(sys.stdin)
for d in dashboards:
    uid = d.get('uid', '')
    folder_uid = d.get('folderUid', 'general')
    title = d.get('title', 'unknown')
    print(f'{uid}|{folder_uid}|{title}')
" 2>/dev/null | while IFS='|' read -r uid folder_uid title; do
            
                # Org/Folder structure
                # We use raw Org Name (Terraform fileset handles spaces if quoted)
                # But safer to sanitize just in case of weird chars, though prompt kept 'Main Org.'
                
                # Sanitize title for filename
                safe_title=$(echo "$title" | sed 's/[\/\\]/-/g')
                
                # Create directory: dashboards/env/Org Name/folder-uid
                TARGET_PATH="${DASH_DIR}/${THIS_ORG_NAME}/${folder_uid}"
                mkdir -p "$TARGET_PATH"

                # Fetch JSON (in context)
                DASH_JSON=$(grafana_api "/api/dashboards/uid/${uid}" || echo "")
                if [ -n "$DASH_JSON" ]; then
                     echo "$DASH_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
dash = data.get('dashboard', {})
dash.pop('id', None)
dash.pop('version', None)
print(json.dumps(dash, indent=2))
" 2>/dev/null > "${TARGET_PATH}/${safe_title}.json"
                     echo -e "  ${GREEN}✓${NC} ${THIS_ORG_NAME}/${folder_uid}/${safe_title}.json"
                fi
            done
            IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
        fi
        
    done <<< "$ORG_LIST_RAW"

    echo -e "  ${GREEN}✓${NC} Exported dashboards to dashboards/${ENV_NAME}/"
else
    echo -e "${BLUE}[7/7]${NC} ${DIM}Skipping dashboards${NC}"
fi

# Reset Context
export CURRENT_ORG_ID=""

# =========================================================================
# Placeholders
# =========================================================================
[ ! -f "${CONFIG_DIR}/sso.yaml" ] && echo "sso:\n  enabled: false" > "${CONFIG_DIR}/sso.yaml"
[ ! -f "${CONFIG_DIR}/keycloak.yaml" ] && echo "keycloak:\n  enabled: false" > "${CONFIG_DIR}/keycloak.yaml"

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
echo ""
if [ "$IMPORT_DASHBOARDS" = true ]; then
    DASH_DIR="${OUTPUT}/dashboards/${ENV_NAME}"
    if [ -d "$DASH_DIR" ]; then
        COUNT=$(find "$DASH_DIR" -name "*.json" 2>/dev/null | wc -l)
        echo "  Dashboards downloaded: $COUNT"
    fi
fi
echo ""
