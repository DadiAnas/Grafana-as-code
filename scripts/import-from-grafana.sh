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
echo -e "${BLUE}[1/8]${NC} Importing organizations..."

ORGS_JSON=$(grafana_api "/api/orgs" || echo "[]")
ORG_COUNT=$(echo "$ORGS_JSON" | (grep -c '"id"' || true))

# Build org_id → org_name mapping for the whole script
declare -A ORG_NAME_MAP
while IFS='|' read -r oid oname; do
    [ -n "$oid" ] && ORG_NAME_MAP[$oid]="$oname"
done < <(echo "$ORGS_JSON" | python3 -c "
import json, sys
try:
    for o in json.load(sys.stdin):
        print(f'{o[\"id\"]}|{o[\"name\"]}')
except: pass
" 2>/dev/null)

# Build list of org IDs for iteration
ORG_IDS=()
while IFS='|' read -r oid oname; do
    [ -n "$oid" ] && ORG_IDS+=("$oid")
done < <(echo "$ORGS_JSON" | python3 -c "
import json, sys
try:
    for o in json.load(sys.stdin):
        print(f'{o[\"id\"]}|{o[\"name\"]}')
except: pass
" 2>/dev/null)

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
# 2. Datasources (all orgs)
# =========================================================================
echo -e "${BLUE}[2/8]${NC} Importing datasources..."

TOTAL_DS=0
{
    echo "# Imported from ${GRAFANA_URL} on $(date -Iseconds)"
    echo ""
    echo "datasources:"

    for ORG_ID in "${ORG_IDS[@]}"; do
        export CURRENT_ORG_ID="$ORG_ID"
        ORG_NAME="${ORG_NAME_MAP[$ORG_ID]:-Org $ORG_ID}"

        DS_JSON=$(grafana_api "/api/datasources" || echo "[]")
        DS_COUNT=$(echo "$DS_JSON" | (grep -c '"id"' || true))

        if [ "$DS_COUNT" -gt 0 ]; then
            echo "$DS_JSON" | python3 -c "
import json, sys
org_name = '$ORG_NAME'
datasources = json.load(sys.stdin)
for ds in datasources:
    print(f'  - name: \"{ds[\"name\"]}\"')
    print(f'    uid: \"{ds.get(\"uid\", ds[\"name\"].lower().replace(\" \", \"-\"))}\"')
    print(f'    type: \"{ds[\"type\"]}\"')
    print(f'    url: \"{ds.get(\"url\", \"\")}\"')
    print(f'    org: \"{org_name}\"')
    print(f'    access: \"{ds.get(\"access\", \"proxy\")}\"')
    print(f'    is_default: {str(ds.get(\"isDefault\", False)).lower()}')
    json_data = ds.get('jsonData', {})
    if json_data:
        print(f'    json_data:')
        for k, v in json_data.items():
            if isinstance(v, bool): print(f'      {k}: {str(v).lower()}')
            elif isinstance(v, (int, float)): print(f'      {k}: {v}')
            else: print(f'      {k}: \"{v}\"')
    print()
" 2>/dev/null
            TOTAL_DS=$((TOTAL_DS + DS_COUNT))
        fi
    done
} > "${CONFIG_DIR}/datasources.yaml"
export CURRENT_ORG_ID=""

if [ "$TOTAL_DS" -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} ${TOTAL_DS} datasource(s) across ${#ORG_IDS[@]} org(s) → config/${ENV_NAME}/datasources.yaml"
    IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
else
    echo -e "  ${DIM}  No datasources found${NC}"
fi

# =========================================================================
# 3. Folders (all orgs)
# =========================================================================
echo -e "${BLUE}[3/8]${NC} Importing folders..."

TOTAL_FOLDERS=0
{
    echo "# Imported from ${GRAFANA_URL} on $(date -Iseconds)"
    echo ""
    echo "folders:"

    for ORG_ID in "${ORG_IDS[@]}"; do
        export CURRENT_ORG_ID="$ORG_ID"
        ORG_NAME="${ORG_NAME_MAP[$ORG_ID]:-Org $ORG_ID}"

        FOLDERS_JSON=$(grafana_api "/api/folders?limit=1000" || echo "[]")
        FOLDER_COUNT=$(echo "$FOLDERS_JSON" | (grep -c '"uid"' || true))

        if [ "$FOLDER_COUNT" -gt 0 ]; then
            echo "$FOLDERS_JSON" | python3 -c "
import json, sys
org_name = '$ORG_NAME'
folders = json.load(sys.stdin)
for f in folders:
    print(f'  - title: \"{f[\"title\"]}\"')
    print(f'    uid: \"{f[\"uid\"]}\"')
    print(f'    org: \"{org_name}\"')
    parent = f.get('parentUid', '')
    if parent:
        print(f'    parent_uid: \"{parent}\"')
    print(f'    permissions: []')
    print()
" 2>/dev/null
            TOTAL_FOLDERS=$((TOTAL_FOLDERS + FOLDER_COUNT))
        fi
    done
} > "${CONFIG_DIR}/folders.yaml"
export CURRENT_ORG_ID=""

# Create dashboard directories for every folder (so Terraform fileset discovers them)
DASH_BASE="${OUTPUT}/dashboards/${ENV_NAME}"
for ORG_ID in "${ORG_IDS[@]}"; do
    export CURRENT_ORG_ID="$ORG_ID"
    ORG_NAME="${ORG_NAME_MAP[$ORG_ID]:-Org $ORG_ID}"

    FOLDERS_JSON=$(grafana_api "/api/folders?limit=1000" || echo "[]")
    echo "$FOLDERS_JSON" | python3 -c "
import json, sys
for f in json.load(sys.stdin):
    print(f.get('uid', ''))
" 2>/dev/null | while read -r fuid; do
        [ -z "$fuid" ] && continue
        mkdir -p "${DASH_BASE}/${ORG_NAME}/${fuid}"
        [ ! -f "${DASH_BASE}/${ORG_NAME}/${fuid}/.gitkeep" ] && touch "${DASH_BASE}/${ORG_NAME}/${fuid}/.gitkeep"
    done
done
export CURRENT_ORG_ID=""

if [ "$TOTAL_FOLDERS" -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} ${TOTAL_FOLDERS} folder(s) across ${#ORG_IDS[@]} org(s) → config/${ENV_NAME}/folders.yaml"
    echo -e "  ${GREEN}✓${NC} Created ${TOTAL_FOLDERS} folder directories under dashboards/${ENV_NAME}/"
    IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
else
    echo -e "  ${DIM}  No folders found${NC}"
fi

# =========================================================================
# 4. Teams (all orgs)
# =========================================================================
echo -e "${BLUE}[4/8]${NC} Importing teams..."

TOTAL_TEAMS=0
{
    echo "# Imported from ${GRAFANA_URL} on $(date -Iseconds)"
    echo ""
    echo "teams:"

    for ORG_ID in "${ORG_IDS[@]}"; do
        export CURRENT_ORG_ID="$ORG_ID"
        ORG_NAME="${ORG_NAME_MAP[$ORG_ID]:-Org $ORG_ID}"

        TEAMS_JSON=$(grafana_api "/api/teams/search?perpage=1000" || echo '{"teams":[]}')
        TEAM_LIST=$(echo "$TEAMS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
teams = data.get('teams', data) if isinstance(data, dict) else data
if isinstance(teams, list):
    for t in teams: print(t.get('name',''))
" 2>/dev/null || true)
        TEAM_COUNT=$(echo "$TEAM_LIST" | grep -c '.' 2>/dev/null || true)

        if [ "$TEAM_COUNT" -gt 0 ] && [ -n "$TEAM_LIST" ]; then
            echo "$TEAMS_JSON" | python3 -c "
import json, sys
org_name = '$ORG_NAME'
data = json.load(sys.stdin)
teams = data.get('teams', data) if isinstance(data, dict) else data
if isinstance(teams, list):
    for t in teams:
        print(f'  - name: \"{t[\"name\"]}\"')
        if t.get('email'): print(f'    email: \"{t[\"email\"]}\"')
        print(f'    org: \"{org_name}\"')
        print(f'    members: []')
        print()
" 2>/dev/null
            TOTAL_TEAMS=$((TOTAL_TEAMS + TEAM_COUNT))
        fi
    done
} > "${CONFIG_DIR}/teams.yaml"
export CURRENT_ORG_ID=""

if [ "$TOTAL_TEAMS" -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} ${TOTAL_TEAMS} team(s) across ${#ORG_IDS[@]} org(s) → config/${ENV_NAME}/teams.yaml"
    IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
else
    echo -e "  ${DIM}  No teams found${NC}"
fi

# =========================================================================
# 5. Service Accounts (all orgs)
# =========================================================================
echo -e "${BLUE}[5/8]${NC} Importing service accounts..."

TOTAL_SA=0
{
    echo "# Imported from ${GRAFANA_URL} on $(date -Iseconds)"
    echo ""
    echo "service_accounts:"

    for ORG_ID in "${ORG_IDS[@]}"; do
        export CURRENT_ORG_ID="$ORG_ID"
        ORG_NAME="${ORG_NAME_MAP[$ORG_ID]:-Org $ORG_ID}"

        SA_JSON=$(grafana_api "/api/serviceaccounts/search?perpage=1000" || echo '{"serviceAccounts":[]}')
        SA_COUNT=$(echo "$SA_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
sas = data.get('serviceAccounts', [])
print(len(sas))
" 2>/dev/null || echo 0)

        if [ "$SA_COUNT" -gt 0 ]; then
            echo "$SA_JSON" | python3 -c "
import json, sys
org_name = '$ORG_NAME'
data = json.load(sys.stdin)
for sa in data.get('serviceAccounts', []):
    print(f'  - name: \"{sa[\"name\"]}\"')
    print(f'    role: \"{sa.get(\"role\", \"Viewer\")}\"')
    print(f'    is_disabled: {str(sa.get(\"isDisabled\", False)).lower()}')
    print(f'    org: \"{org_name}\"')
    print()
" 2>/dev/null
            TOTAL_SA=$((TOTAL_SA + SA_COUNT))
        fi
    done
} > "${CONFIG_DIR}/service_accounts.yaml"
export CURRENT_ORG_ID=""

if [ "$TOTAL_SA" -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} ${TOTAL_SA} service account(s) across ${#ORG_IDS[@]} org(s) → config/${ENV_NAME}/service_accounts.yaml"
    IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
else
    echo -e "  ${DIM}  No service accounts found${NC}"
fi

# =========================================================================
# 6. Alert Rules & Contact Points (all orgs)
# =========================================================================
echo -e "${BLUE}[6/8]${NC} Importing alerting configuration..."

TOTAL_CP=0
{
    echo "# Imported from ${GRAFANA_URL} on $(date -Iseconds)"
    echo ""
    echo "contactPoints:"

    for ORG_ID in "${ORG_IDS[@]}"; do
        export CURRENT_ORG_ID="$ORG_ID"
        ORG_NAME="${ORG_NAME_MAP[$ORG_ID]:-Org $ORG_ID}"

        CP_JSON=$(grafana_api "/api/v1/provisioning/contact-points" || echo "[]")
        CP_COUNT=$(echo "$CP_JSON" | (grep -c '"uid"' || true))

        if [ "$CP_COUNT" -gt 0 ]; then
            echo "$CP_JSON" | python3 -c "
import json, sys
org_name = '$ORG_NAME'
cps = json.load(sys.stdin)
grouped = {}
for cp in cps:
    name = cp['name']
    if name not in grouped: grouped[name] = {'name': name, 'receivers': []}
    grouped[name]['receivers'].append({'type': cp['type'], 'settings': cp.get('settings', {})})
for name, cp in grouped.items():
    print(f'  - name: \"{name}\"')
    print(f'    org: \"{org_name}\"')
    print(f'    receivers:')
    for r in cp['receivers']:
        print(f'      - type: \"{r[\"type\"]}\"')
        if r['settings']:
            print(f'        settings:')
            for k, v in r['settings'].items():
                if isinstance(v, str): print(f'          {k}: \"{v}\"')
                elif isinstance(v, bool): print(f'          {k}: {str(v).lower()}')
                else: print(f'          {k}: {v}')
    print()
" 2>/dev/null
            TOTAL_CP=$((TOTAL_CP + CP_COUNT))
        fi
    done
} > "${CONFIG_DIR}/alerting/contact_points.yaml"
export CURRENT_ORG_ID=""

if [ "$TOTAL_CP" -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} ${TOTAL_CP} contact point(s) across ${#ORG_IDS[@]} org(s)"
    IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
fi

TOTAL_AR=0
{
    echo "# Imported from ${GRAFANA_URL} on $(date -Iseconds)"
    echo ""
    echo "groups:"

    for ORG_ID in "${ORG_IDS[@]}"; do
        export CURRENT_ORG_ID="$ORG_ID"
        ORG_NAME="${ORG_NAME_MAP[$ORG_ID]:-Org $ORG_ID}"

        AR_JSON=$(grafana_api "/api/v1/provisioning/alert-rules" || echo "[]")
        AR_COUNT=$(echo "$AR_JSON" | (grep -c '"uid"' || true))

        if [ "$AR_COUNT" -gt 0 ]; then
            echo "$AR_JSON" | python3 -c "
import json, sys
org_name = '$ORG_NAME'
rules = json.load(sys.stdin)
groups = {}
for rule in rules:
    folder = rule.get('folderUID', 'general')
    group_name = rule.get('ruleGroup', 'default')
    key = f'{folder}/{group_name}'
    if key not in groups:
        groups[key] = {'name': group_name, 'folder': folder, 'rules': []}
    groups[key]['rules'].append(rule)
for key, g in groups.items():
    print(f'  - name: \"{g[\"name\"]}\"')
    print(f'    folder: \"{g[\"folder\"]}\"')
    print(f'    org: \"{org_name}\"')
    print(f'    interval: \"1m\"')
    print(f'    rules:')
    for r in g['rules']:
        print(f'      - title: \"{r.get(\"title\", \"\")}\"')
        print(f'        condition: \"{r.get(\"condition\", \"\")}\"')
        print(f'        for: \"{r.get(\"for\", \"5m\")}\"')
    print()
" 2>/dev/null
            TOTAL_AR=$((TOTAL_AR + AR_COUNT))
        fi
    done
} > "${CONFIG_DIR}/alerting/alert_rules.yaml"
export CURRENT_ORG_ID=""

if [ "$TOTAL_AR" -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} ${TOTAL_AR} alert rule(s) across ${#ORG_IDS[@]} org(s)"
    IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
fi

# Placeholder for notification policies
cat > "${CONFIG_DIR}/alerting/notification_policies.yaml" << EOF
# Imported from ${GRAFANA_URL} on $(date -Iseconds)
# NOTE: Notification policies need manual configuration.
policies: []
EOF

# =========================================================================
# 7. Dashboards (all orgs)
# =========================================================================
if [ "$IMPORT_DASHBOARDS" = true ]; then
    echo -e "${BLUE}[7/8]${NC} Importing dashboards..."

    DASH_DIR="${OUTPUT}/dashboards/${ENV_NAME}"

    for ORG_ID in "${ORG_IDS[@]}"; do
        export CURRENT_ORG_ID="$ORG_ID"
        ORG_NAME="${ORG_NAME_MAP[$ORG_ID]:-Org $ORG_ID}"

        SEARCH_JSON=$(grafana_api "/api/search?type=dash-db&limit=5000" || echo "[]")
        DASH_COUNT=$(echo "$SEARCH_JSON" | (grep -c '"uid"' || true))

        if [ "$DASH_COUNT" -gt 0 ]; then
            echo "$SEARCH_JSON" | python3 -c "
import json, sys
dashboards = json.load(sys.stdin)
for d in dashboards:
    uid = d.get('uid', '')
    folder_uid = d.get('folderUid', 'general')
    title = d.get('title', 'unknown')
    print(f'{uid}|{folder_uid}|{title}')
" 2>/dev/null | while IFS='|' read -r uid folder_uid title; do
                [ -z "$folder_uid" ] && folder_uid="general"
                safe_title=$(echo "$title" | sed 's/[\/\\]/-/g')

                mkdir -p "${DASH_DIR}/${ORG_NAME}/${folder_uid}"

                DASH_JSON=$(grafana_api "/api/dashboards/uid/${uid}" || echo "")
                if [ -n "$DASH_JSON" ]; then
                    echo "$DASH_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
dash = data.get('dashboard', {})
dash.pop('id', None)
dash.pop('version', None)
print(json.dumps(dash, indent=2))
" 2>/dev/null > "${DASH_DIR}/${ORG_NAME}/${folder_uid}/${safe_title}.json"
                    echo -e "  ${GREEN}✓${NC} ${ORG_NAME}/${folder_uid}/${safe_title}.json"
                fi
            done
        fi
    done
    export CURRENT_ORG_ID=""

    echo -e "  ${GREEN}✓${NC} Exported dashboards to dashboards/${ENV_NAME}/"
    IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
else
    echo -e "${BLUE}[7/8]${NC} ${DIM}Skipping dashboards (--no-dashboards)${NC}"
fi

# =========================================================================
# 8. SSO Settings
# =========================================================================
echo -e "${BLUE}[8/8]${NC} Importing SSO settings..."

SSO_JSON=$(grafana_api "/api/v1/sso-settings" || echo "[]")
SSO_COUNT=$(echo "$SSO_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
enabled = [p for p in data if p.get('settings', {}).get('enabled', False)]
print(len(enabled))
" 2>/dev/null || echo 0)

{
    echo "# Imported from ${GRAFANA_URL} on $(date -Iseconds)"
    echo "# SSO providers found: total=$(echo "$SSO_JSON" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0), enabled=${SSO_COUNT}"
    echo ""
    echo "$SSO_JSON" | python3 -c "
import json, sys, yaml

data = json.load(sys.stdin)
result = {'sso': {'providers': []}}

for provider in data:
    name = provider.get('provider', '')
    settings = provider.get('settings', {})
    enabled = settings.get('enabled', False)
    source = provider.get('source', 'system')

    entry = {
        'provider': name,
        'enabled': enabled,
        'source': source,
    }

    # Only include meaningful settings for enabled providers
    if enabled:
        important_keys = [
            'name', 'clientId', 'authUrl', 'tokenUrl', 'apiUrl',
            'scopes', 'allowSignUp', 'autoLogin', 'allowedDomains',
            'allowedOrganizations', 'allowedGroups', 'roleAttributePath',
            'orgMapping', 'skipOrgRoleSync', 'usePkce', 'icon',
            'teamIds', 'hostedDomain'
        ]
        entry['settings'] = {}
        for k in important_keys:
            v = settings.get(k)
            if v is not None and v != '' and v != False:
                entry['settings'][k] = v
        # Note: clientSecret is never returned by the API
        entry['settings']['clientSecret'] = '** SET IN VAULT **'

    result['sso']['providers'].append(entry)

print(yaml.dump(result, default_flow_style=False, sort_keys=False))
" 2>/dev/null || python3 -c "
import json, sys

# Fallback if PyYAML is not installed
data = json.load(sys.stdin)
print('sso:')
print('  providers:')
for provider in data:
    name = provider.get('provider', '')
    settings = provider.get('settings', {})
    enabled = settings.get('enabled', False)
    source = provider.get('source', 'system')
    print(f'    - provider: \"{name}\"')
    print(f'      enabled: {str(enabled).lower()}')
    print(f'      source: \"{source}\"')
    if enabled:
        client_id = settings.get('clientId', '')
        auth_url = settings.get('authUrl', '')
        token_url = settings.get('tokenUrl', '')
        scopes = settings.get('scopes', '')
        if client_id: print(f'      client_id: \"{client_id}\"')
        if auth_url: print(f'      auth_url: \"{auth_url}\"')
        if token_url: print(f'      token_url: \"{token_url}\"')
        if scopes: print(f'      scopes: \"{scopes}\"')
        print(f'      client_secret: \"** SET IN VAULT **\"')
    print()
" <<< "$SSO_JSON" 2>/dev/null
} > "${CONFIG_DIR}/sso.yaml"

if [ "$SSO_COUNT" -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} ${SSO_COUNT} enabled SSO provider(s) → config/${ENV_NAME}/sso.yaml"
else
    echo -e "  ${DIM}  No enabled SSO providers (all providers saved as reference)${NC}"
fi
IMPORTED_COUNT=$((IMPORTED_COUNT + 1))

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
echo "  Orgs:        ${#ORG_IDS[@]} (${ORG_IDS[*]})"
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
        # Show breakdown per org
        for ORG_ID in "${ORG_IDS[@]}"; do
            ORG_NAME="${ORG_NAME_MAP[$ORG_ID]:-Org $ORG_ID}"
            if [ -d "${DASH_DIR}/${ORG_NAME}" ]; then
                ORG_DASH_COUNT=$(find "${DASH_DIR}/${ORG_NAME}" -name "*.json" 2>/dev/null | wc -l)
                echo "      ${ORG_NAME}: ${ORG_DASH_COUNT} dashboards"
            fi
        done
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
