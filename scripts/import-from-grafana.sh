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
    local opts=("-sf" "--connect-timeout" "5" "--max-time" "15")

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
import json, sys, re, copy

try:
    import yaml
    HAS_YAML = True
except ImportError:
    HAS_YAML = False

org_name = '$ORG_NAME'
org_id = $ORG_ID
datasources = json.load(sys.stdin)

def simple_yaml_val(k, v, indent=6):
    prefix = ' ' * indent
    if isinstance(v, bool):
        print(f'{prefix}{k}: {str(v).lower()}')
    elif isinstance(v, (int, float)):
        print(f'{prefix}{k}: {v}')
    elif isinstance(v, dict):
        print(f'{prefix}{k}:')
        for dk, dv in v.items():
            simple_yaml_val(dk, dv, indent + 2)
    elif isinstance(v, list):
        print(f'{prefix}{k}:')
        sub = ' ' * (indent + 2)
        for item in v:
            if isinstance(item, dict):
                first = True
                for dk, dv in item.items():
                    if first:
                        print(f'{sub}- {dk}: {json.dumps(dv) if not isinstance(dv, str) else dv}')
                        first = False
                    else:
                        simple_yaml_val(dk, dv, indent + 4)
            else:
                print(f'{sub}- {json.dumps(item) if not isinstance(item, str) else item}')
    elif v is None:
        print(f'{prefix}{k}: null')
    else:
        s = str(v)
        print(f'{prefix}{k}: \"{s}\"')

for ds in datasources:
    ds_type = ds['type']
    json_data = copy.deepcopy(ds.get('jsonData', {}))
    secure_fields = ds.get('secureJsonFields', {})

    # ---- Extract httpHeaderName*/httpHeaderValue* into http_headers ----
    http_headers = {}
    header_keys_to_remove = []
    for k, v in list(json_data.items()):
        m = re.match(r'^httpHeaderName(\d+)$', k)
        if m:
            idx = m.group(1)
            header_name = str(v)
            header_keys_to_remove.append(k)
            val_key = f'httpHeaderValue{idx}'
            if val_key in json_data:
                http_headers[header_name] = str(json_data[val_key])
                header_keys_to_remove.append(val_key)
            else:
                http_headers[header_name] = ''
        elif re.match(r'^httpHeaderValue\d+$', k):
            header_keys_to_remove.append(k)
    for hk in set(header_keys_to_remove):
        json_data.pop(hk, None)

    # ---- Core fields ----
    print(f'  - name: \"{ds[\"name\"]}\"')
    print(f'    uid: \"{ds.get(\"uid\", ds[\"name\"].lower().replace(\" \", \"-\"))}\"')
    print(f'    type: \"{ds_type}\"')
    print(f'    url: \"{ds.get(\"url\", \"\")}\"')
    print(f'    org: \"{org_name}\"')
    print(f'    orgId: {org_id}')
    print(f'    access: \"{ds.get(\"access\", \"proxy\")}\"')
    print(f'    is_default: {str(ds.get(\"isDefault\", False)).lower()}')

    # ---- Basic auth ----
    if ds.get('basicAuth'):
        print(f'    basic_auth_enabled: true')
        if ds.get('basicAuthUser'):
            print(f'    basic_auth_username: \"{ds[\"basicAuthUser\"]}\"')

    # ---- Database / username (postgres, mysql, etc.) ----
    if ds.get('database'):
        print(f'    database_name: \"{ds[\"database\"]}\"')
    if ds.get('user'):
        print(f'    username: \"{ds[\"user\"]}\"')

    # ---- json_data: type-aware extraction ----
    # For these types, we pull well-known keys out as first-class YAML
    # and also keep the full json_data for anything else.

    if json_data:
        if HAS_YAML:
            # Use PyYAML for proper nested structure output
            rendered = yaml.dump({'json_data': json_data}, default_flow_style=False, sort_keys=False).rstrip()
            for line in rendered.split('\n'):
                print(f'    {line}')
        else:
            print(f'    json_data:')
            for k, v in json_data.items():
                simple_yaml_val(k, v, 6)

    # ---- http_headers ----
    if http_headers:
        print(f'    http_headers:')
        for hname, hval in http_headers.items():
            print(f'      \"{hname}\": \"{hval}\"')

    # ---- secure_json_data placeholder for fields the API masks ----
    if secure_fields:
        print(f'    # NOTE: secure fields detected (values hidden by Grafana API)')
        print(f'    # Configure via Vault (use_vault: true) or set manually:')
        print(f'    # secure_json_data:')
        for sk in secure_fields:
            print(f'    #   {sk}: \"\"')

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
import json, sys, subprocess, os

org_name = '$ORG_NAME'
org_id = $ORG_ID
grafana_url = os.environ.get('GRAFANA_URL', '${GRAFANA_URL}')
auth = os.environ.get('AUTH', '${AUTH}')
folders = json.load(sys.stdin)

# Build team id->name map for this org
try:
    result = subprocess.run(
        ['curl', '-sf', '-u', auth, '-H', f'X-Grafana-Org-Id: {org_id}',
         f'{grafana_url}/api/teams/search?perpage=1000'],
        capture_output=True, text=True, timeout=10)
    teams_data = json.loads(result.stdout) if result.returncode == 0 else {}
    team_map = {t['id']: t['name'] for t in teams_data.get('teams', [])}
except Exception:
    team_map = {}

# Build user id->login map for this org
try:
    result = subprocess.run(
        ['curl', '-sf', '-u', auth, '-H', f'X-Grafana-Org-Id: {org_id}',
         f'{grafana_url}/api/org/users?perpage=1000'],
        capture_output=True, text=True, timeout=10)
    users_data = json.loads(result.stdout) if result.returncode == 0 else []
    user_map = {u['userId']: u['login'] for u in users_data}
except Exception:
    user_map = {}

for f in folders:
    print(f'  - title: \"{f[\"title\"]}\"')
    print(f'    uid: \"{f[\"uid\"]}\"')
    print(f'    org: \"{org_name}\"')
    print(f'    orgId: {org_id}')
    parent = f.get('parentUid', '')
    if parent:
        print(f'    parent_uid: \"{parent}\"')

    # Fetch folder permissions
    try:
        result = subprocess.run(
            ['curl', '-sf', '-u', auth, '-H', f'X-Grafana-Org-Id: {org_id}',
             f'{grafana_url}/api/folders/{f[\"uid\"]}/permissions'],
            capture_output=True, text=True, timeout=10)
        perms = json.loads(result.stdout) if result.returncode == 0 else []
    except Exception:
        perms = []

    # Filter to non-inherited, non-zero permissions
    explicit_perms = [p for p in perms if not p.get('inherited', False) and p.get('permission', 0) > 0]

    if not explicit_perms:
        print(f'    permissions: []')
    else:
        perm_names = {1: 'View', 2: 'Edit', 4: 'Admin'}
        print(f'    permissions:')
        for p in explicit_perms:
            perm_str = perm_names.get(p['permission'], str(p['permission']))
            if p.get('teamId', 0) > 0:
                team_name = team_map.get(p['teamId'], f'team-{p[\"teamId\"]}')
                print(f'      - team: \"{team_name}\"')
                print(f'        permission: \"{perm_str}\"')
            elif p.get('userId', 0) > 0:
                user_login = user_map.get(p['userId'], f'user-{p[\"userId\"]}')
                print(f'      - user: \"{user_login}\"')
                print(f'        permission: \"{perm_str}\"')
            elif p.get('role', ''):
                print(f'      - role: \"{p[\"role\"]}\"')
                print(f'        permission: \"{perm_str}\"')
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
        [ ! -f "${DASH_BASE}/${ORG_NAME}/${fuid}/.gitkeep" ] && touch "${DASH_BASE}/${ORG_NAME}/${fuid}/.gitkeep" || true
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
            # Try to fetch external group mappings per team (Enterprise/Cloud only)
            # Build a JSON map of team_id -> [group_names]
            TEAM_GROUPS_MAP="{}"
            # Get team IDs from the JSON
            TEAM_IDS_LIST=$(echo "$TEAMS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
teams = data.get('teams', data) if isinstance(data, dict) else data
if isinstance(teams, list):
    for t in teams: print(t.get('id',''))
" 2>/dev/null || true)

            if [ -n "$TEAM_IDS_LIST" ]; then
                TEAM_GROUPS_MAP=$(
                    echo "{"
                    FIRST=true
                    while IFS= read -r TID; do
                        [ -z "$TID" ] && continue
                        GROUPS_RESP=$(grafana_api "/api/teams/$TID/groups" 2>/dev/null || echo "")
                        # Parse response — if it's a JSON array of objects with groupId field
                        GROUPS_LIST=$(echo "$GROUPS_RESP" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if isinstance(data, list):
        groups = [g.get('groupId', '') for g in data if g.get('groupId')]
        if groups:
            print(json.dumps(groups))
except: pass
" 2>/dev/null || true)
                        if [ -n "$GROUPS_LIST" ]; then
                            if [ "$FIRST" = true ]; then FIRST=false; else echo ","; fi
                            echo "\"$TID\": $GROUPS_LIST"
                        fi
                    done <<< "$TEAM_IDS_LIST"
                    echo "}"
                )
            fi

            echo "$TEAMS_JSON" | TEAM_GROUPS="$TEAM_GROUPS_MAP" python3 -c "
import json, sys, os
org_name = '$ORG_NAME'
org_id = $ORG_ID
data = json.load(sys.stdin)
try:
    team_groups = json.loads(os.environ.get('TEAM_GROUPS', '{}'))
except:
    team_groups = {}
teams = data.get('teams', data) if isinstance(data, dict) else data
if isinstance(teams, list):
    for t in teams:
        print(f'  - name: \"{t[\"name\"]}\"')
        if t.get('email'): print(f'    email: \"{t[\"email\"]}\"')
        print(f'    org: \"{org_name}\"')
        print(f'    orgId: {org_id}')
        # External group sync (Enterprise/Cloud)
        ext_groups = team_groups.get(str(t.get('id', '')), [])
        if ext_groups:
            print(f'    external_groups:')
            for g in ext_groups:
                print(f'      - \"{g}\"')
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
org_id = $ORG_ID
data = json.load(sys.stdin)
for sa in data.get('serviceAccounts', []):
    print(f'  - name: \"{sa[\"name\"]}\"')
    print(f'    role: \"{sa.get(\"role\", \"Viewer\")}\"')
    print(f'    is_disabled: {str(sa.get(\"isDisabled\", False)).lower()}')
    print(f'    org: \"{org_name}\"')
    print(f'    orgId: {org_id}')
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
try:
    import yaml
    HAS_YAML = True
except ImportError:
    HAS_YAML = False

org_name = '$ORG_NAME'
cps = json.load(sys.stdin)
grouped = {}
for cp in cps:
    name = cp['name']
    if name not in grouped: grouped[name] = {'name': name, 'receivers': []}
    recv = {'type': cp['type']}
    settings = cp.get('settings', {})
    if settings:
        recv['settings'] = settings
    dis_resolve = cp.get('disableResolveMessage')
    if dis_resolve is not None:
        recv['disableResolveMessage'] = dis_resolve
    grouped[name]['receivers'].append(recv)

for name, cp in grouped.items():
    entry = {'name': name, 'org': org_name, 'orgId': int('$ORG_ID'), 'receivers': cp['receivers']}
    if HAS_YAML:
        lines = yaml.dump([entry], default_flow_style=False, sort_keys=False).rstrip()
        # indent to match contactPoints array
        for line in lines.split('\n'):
            print(f'  {line}')
    else:
        print(f'  - name: \"{name}\"')
        print(f'    org: \"{org_name}\"')
        print(f'    orgId: $ORG_ID')
        print(f'    receivers:')
        for r in cp['receivers']:
            print(f'      - type: \"{r[\"type\"]}\"')
            if r.get('settings'):
                print(f'        settings:')
                for k, v in r['settings'].items():
                    if isinstance(v, str):
                        if '\n' in v:
                            print(f'          {k}: |')
                            for sl in v.split('\n'): print(f'            {sl}')
                        else:
                            print(f'          {k}: \"{v}\"')
                    elif isinstance(v, bool): print(f'          {k}: {str(v).lower()}')
                    elif isinstance(v, dict):
                        print(f'          {k}:')
                        for dk, dv in v.items(): print(f'            {dk}: \"{dv}\"')
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
import json, sys, yaml

class NoAliasDumper(yaml.SafeDumper):
    def ignore_aliases(self, data):
        return True

org_name = '$ORG_NAME'
try:
    rules = json.load(sys.stdin)
except:
    rules = []

groups = {}
for rule in rules:
    folder = rule.get('folderUID', 'general')
    group_name = rule.get('ruleGroup', 'default')
    key = f'{folder}/{group_name}'
    
    if key not in groups:
        groups[key] = {
            'name': group_name,
            'folder': folder,
            'org': org_name,
            'orgId': int('$ORG_ID'),
            'interval': '1m',
            'rules': []
        }
    
    # Construct rule object with all fields required by the module
    r_data = {
        'title': rule.get('title', rule.get('name', 'Alert')),
        'condition': rule.get('condition', ''),
        'for': rule.get('for', '5m'),
        'annotations': rule.get('annotations', {}),
        'labels': rule.get('labels', {}),
        'noDataState': rule.get('noDataState', 'NoData'),
        'execErrState': rule.get('execErrState', 'Error'),
        'data': rule.get('data', [])
    }
    groups[key]['rules'].append(r_data)

if groups:
    # Dump as list of groups
    print(yaml.dump(list(groups.values()), Dumper=NoAliasDumper, sort_keys=False))
" 2>/dev/null | sed 's/^/  /'
            TOTAL_AR=$((TOTAL_AR + AR_COUNT))
        fi
    done
} > "${CONFIG_DIR}/alerting/alert_rules.yaml"
export CURRENT_ORG_ID=""

if [ "$TOTAL_AR" -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} ${TOTAL_AR} alert rule(s) across ${#ORG_IDS[@]} org(s)"
    IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
fi

# -------------------------------------------------------------------------
# Notification Policies (all orgs)
# -------------------------------------------------------------------------

TOTAL_NP=0
{
    echo "# Imported from ${GRAFANA_URL} on $(date -Iseconds)"
    echo "#"
    echo "# Notification Policies define how alerts are routed to contact points."
    echo "# Format follows Grafana's provisioning API structure."
    echo ""
    echo "policies:"

    for ORG_ID in "${ORG_IDS[@]}"; do
        export CURRENT_ORG_ID="$ORG_ID"
        ORG_NAME="${ORG_NAME_MAP[$ORG_ID]:-Org $ORG_ID}"

        NP_JSON=$(grafana_api "/api/v1/provisioning/policies" || echo "{}")

        # Check if we got a valid policy tree (must have a receiver)
        HAS_RECEIVER=$(echo "$NP_JSON" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print('yes' if data.get('receiver') else 'no')
except:
    print('no')
" 2>/dev/null || echo "no")

        if [ "$HAS_RECEIVER" = "yes" ]; then
            echo "$NP_JSON" | python3 -c "
import json, sys

org_id = $ORG_ID
org_name = '$ORG_NAME'

def emit_route(route, indent):
    \"\"\"Recursively emit a route (child policy) as YAML.\"\"\"
    prefix = '  ' * indent

    receiver = route.get('receiver')
    if receiver:
        print(f'{prefix}- receiver: {receiver}')
    else:
        print(f'{prefix}- receiver: null')

    group_by = route.get('group_by')
    if group_by:
        print(f'{prefix}  group_by:')
        for g in group_by:
            print(f'{prefix}    - {g}')

    matchers = route.get('object_matchers', [])
    if matchers:
        print(f'{prefix}  object_matchers:')
        for m in matchers:
            # Each matcher is [label, operator, value]
            if isinstance(m, list) and len(m) == 3:
                print(f'{prefix}    - - {m[0]}')
                print(f'{prefix}      - \"{m[1]}\"')
                print(f'{prefix}      - {m[2]}')

    cont = route.get('continue')
    if cont is not None:
        print(f'{prefix}  continue: {str(cont).lower()}')

    gw = route.get('group_wait')
    if gw:
        print(f'{prefix}  group_wait: {gw}')

    gi = route.get('group_interval')
    if gi:
        print(f'{prefix}  group_interval: {gi}')

    ri = route.get('repeat_interval')
    if ri:
        print(f'{prefix}  repeat_interval: {ri}')

    # mute_time_intervals from API → mute_timings in YAML (what Terraform expects)
    mute = route.get('mute_time_intervals', [])
    if mute:
        print(f'{prefix}  mute_timings:')
        for mt in mute:
            print(f'{prefix}    - {mt}')

    # Nested routes (recursive)
    child_routes = route.get('routes', [])
    if child_routes:
        print(f'{prefix}  routes:')
        for child in child_routes:
            emit_route(child, indent + 2)


try:
    data = json.load(sys.stdin)
except:
    sys.exit(0)

# Root-level policy
print(f'  - orgId: {org_id}')
print(f'    org: \"{org_name}\"')
print(f'    receiver: {data.get(\"receiver\", \"grafana-default-email\")}')

group_by = data.get('group_by')
if group_by:
    print(f'    group_by:')
    for g in group_by:
        print(f'      - {g}')

gw = data.get('group_wait')
if gw:
    print(f'    group_wait: {gw}')

gi = data.get('group_interval')
if gi:
    print(f'    group_interval: {gi}')

ri = data.get('repeat_interval')
if ri:
    print(f'    repeat_interval: {ri}')

# Root-level mute_time_intervals → mute_timings
mute = data.get('mute_time_intervals', [])
if mute:
    print(f'    mute_timings:')
    for mt in mute:
        print(f'      - {mt}')

# Child routes
routes = data.get('routes', [])
if routes:
    print(f'    routes:')
    for route in routes:
        emit_route(route, 3)

print()
" 2>/dev/null
            TOTAL_NP=$((TOTAL_NP + 1))
        fi
    done
} > "${CONFIG_DIR}/alerting/notification_policies.yaml"
export CURRENT_ORG_ID=""

if [ "$TOTAL_NP" -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} ${TOTAL_NP} notification policy tree(s) across ${#ORG_IDS[@]} org(s)"
    IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
else
    echo -e "  ${DIM}  No notification policies found${NC}"
fi

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

# Build org_id->org_name JSON map for the python script
ORG_MAP_JSON=$(echo "$ORGS_JSON" | python3 -c "
import json, sys
orgs = json.load(sys.stdin)
print(json.dumps({str(o['id']): o['name'] for o in orgs}))
" 2>/dev/null || echo "{}")

{
    echo "$SSO_JSON" | ORG_MAP="$ORG_MAP_JSON" python3 -c "
import json, sys, os

data = json.load(sys.stdin)
org_map = json.loads(os.environ.get('ORG_MAP', '{}'))

# Find the first enabled provider (generic_oauth preferred)
enabled_provider = None
for p in data:
    if p.get('settings', {}).get('enabled', False):
        if p.get('provider') == 'generic_oauth' or enabled_provider is None:
            enabled_provider = p

print('# Imported from Grafana SSO settings')
print('#')
print('# This file follows the project format expected by modules/sso.')
print('# Client secret is stored in Vault — see vault-setup.')
print()

if enabled_provider is None:
    print('sso:')
    print('  enabled: false')
else:
    s = enabled_provider.get('settings', {})
    provider_type = enabled_provider.get('provider', 'generic_oauth')

    print('sso:')
    print(f'  enabled: true')
    print(f'  name: \"{s.get(\"name\", provider_type)}\"')
    print()
    print(f'  # OAuth2 endpoints')
    print(f'  auth_url: \"{s.get(\"authUrl\", \"\")}\"')
    print(f'  token_url: \"{s.get(\"tokenUrl\", \"\")}\"')
    print(f'  api_url: \"{s.get(\"apiUrl\", \"\")}\"')
    print()
    print(f'  # Client configuration (client_secret stored in Vault)')
    print(f'  client_id: \"{s.get(\"clientId\", \"\")}\"')
    print()
    print(f'  # OAuth settings')
    print(f'  allow_sign_up: {str(s.get(\"allowSignUp\", True)).lower()}')
    print(f'  auto_login: {str(s.get(\"autoLogin\", False)).lower()}')
    print(f'  scopes: \"{s.get(\"scopes\", \"openid profile email groups\")}\"')
    print(f'  use_pkce: {str(s.get(\"usePkce\", True)).lower()}')
    print(f'  use_refresh_token: {str(s.get(\"useRefreshToken\", True)).lower()}')
    print()

    # Role mapping
    rap = s.get('roleAttributePath', '')
    if rap:
        print(f'  role_attribute_path: \"{rap}\"')
    print(f'  role_attribute_strict: {str(s.get(\"roleAttributeStrict\", False)).lower()}')
    print(f'  skip_org_role_sync: {str(s.get(\"skipOrgRoleSync\", False)).lower()}')
    print()

    # Groups attribute
    gap = s.get('groupsAttributePath', '')
    if gap:
        print(f'  groups_attribute_path: \"{gap}\"')
    print()

    # Allowed groups
    ag = s.get('allowedGroups', '')
    if ag:
        print(f'  allowed_groups: \"{ag}\"')
        print()

    # Parse org_mapping into groups format
    org_mapping_str = s.get('orgMapping', '')
    if org_mapping_str:
        print('  # Group-to-org role mappings')
        print('  # Generated from Grafana org_mapping config')
        print('  # Use org: \"*\" to apply a role to all organizations')
        print('  groups:')
        # org_mapping format: group_name:org_id_or_*:role (newline separated)
        mappings = [m.strip() for m in org_mapping_str.strip().replace('\\n', '\n').split('\n') if m.strip()]

        # Collect all known org IDs from the org_map
        all_org_ids = set(org_map.keys())

        groups = {}
        group_order = []
        for m in mappings:
            parts = m.split(':')
            if len(parts) >= 3:
                group_name = parts[0]
                org_id = parts[1]
                role = parts[2]
                if group_name not in groups:
                    groups[group_name] = []
                    group_order.append(group_name)
                if org_id == '*':
                    # Wildcard already in source — preserve it
                    groups[group_name].append({'org': '*', 'role': role})
                else:
                    org_name = org_map.get(org_id, org_id)
                    groups[group_name].append({'org': org_name, 'role': role, '_org_id': org_id})

        # Collapse: if a group maps to ALL orgs with the same role, use org: \"*\"
        for group_name in group_order:
            mappings_list = groups[group_name]
            # Skip if already contains a wildcard
            if any(m['org'] == '*' for m in mappings_list):
                continue
            # Check by role: count how many orgs share the same role
            role_counts = {}
            for m in mappings_list:
                role_counts.setdefault(m['role'], []).append(m)
            # If one role covers ALL known orgs, collapse to *
            for role, role_mappings in role_counts.items():
                covered_ids = {m['_org_id'] for m in role_mappings}
                if len(all_org_ids) > 1 and covered_ids >= all_org_ids:
                    # This role covers all orgs — collapse to *
                    remaining = [m for m in mappings_list if m['role'] != role]
                    remaining.insert(0, {'org': '*', 'role': role})
                    groups[group_name] = remaining
                    break

        for group_name in group_order:
            print(f'    - name: \"{group_name}\"')
            print(f'      org_mappings:')
            for om in groups[group_name]:
                print(f'        - org: \"{om[\"org\"]}\"')
                print(f'          role: \"{om[\"role\"]}\"')
    print()

    # Teams
    tu = s.get('teamsUrl', '')
    if tu:
        print(f'  teams_url: \"{tu}\"')
    tiap = s.get('teamIdsAttributePath', '')
    if tiap:
        print(f'  team_ids_attribute_path: \"{tiap}\"')

    # Signout
    sru = s.get('signoutRedirectUrl', '')
    if sru:
        print(f'  signout_redirect_url: \"{sru}\"')
" 2>/dev/null
} > "${CONFIG_DIR}/sso.yaml"

# Check if SSO was enabled
SSO_ENABLED=$(echo "$SSO_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
enabled = [p for p in data if p.get('settings', {}).get('enabled', False)]
print(len(enabled))
" 2>/dev/null || echo 0)

if [ "$SSO_ENABLED" -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} SSO config (enabled) → config/${ENV_NAME}/sso.yaml"
else
    echo -e "  ${DIM}  SSO disabled → config/${ENV_NAME}/sso.yaml${NC}"
fi
IMPORTED_COUNT=$((IMPORTED_COUNT + 1))

[ ! -f "${CONFIG_DIR}/keycloak.yaml" ] && cat > "${CONFIG_DIR}/keycloak.yaml" << EOFKC
# Keycloak configuration — must be configured manually

keycloak:
  enabled: false
  realm_id: "master"
  client_id: "grafana"
  root_url: "${GRAFANA_URL}"
EOFKC

# Clean up any orphaned Keycloak resources from Terraform state
# (keycloak.yaml defaults to enabled: false, so state entries would cause errors)
KC_STATE=$(terraform state list 2>/dev/null | grep '^module\.keycloak\.' || true)
if [ -n "$KC_STATE" ]; then
    echo -e "  ${YELLOW}Removing orphaned Keycloak resources from Terraform state...${NC}"
    echo "$KC_STATE" | while IFS= read -r resource; do
        terraform state rm "$resource" >/dev/null 2>&1 || true
    done
    echo -e "  ${GREEN}✓${NC} Cleaned $(echo "$KC_STATE" | wc -l) Keycloak state entries"
fi

# =========================================================================
# Generate tfvars file
# =========================================================================
TFVARS_FILE="${OUTPUT}/environments/${ENV_NAME}.tfvars"
if [ ! -f "$TFVARS_FILE" ]; then
    mkdir -p "${OUTPUT}/environments"
    cat > "$TFVARS_FILE" << EOFVARS
# =============================================================================
# ${ENV_NAME^^} ENVIRONMENT - Terraform Variables
# =============================================================================
# Auto-generated by import-from-grafana.sh on $(date -Iseconds)
#
# Usage:
#   make plan  ENV=${ENV_NAME}
#   make apply ENV=${ENV_NAME}
# =============================================================================

# The URL of your Grafana instance
grafana_url = "${GRAFANA_URL}"

# Environment name — must match a directory under config/ and dashboards/
environment = "${ENV_NAME}"

# Vault Configuration (HashiCorp Vault for secrets management)
vault_address = "http://localhost:8200"
vault_mount   = "grafana"
# vault_token — set via VAULT_TOKEN env variable for security:
#   export VAULT_TOKEN="your-vault-token"

# Keycloak Configuration (optional — only if you enable SSO via Keycloak)
# keycloak_url = "https://keycloak.example.com"
EOFVARS
    echo -e "  ${GREEN}✓${NC} Generated environments/${ENV_NAME}.tfvars"
else
    echo -e "  ${DIM}  environments/${ENV_NAME}.tfvars already exists (skipped)${NC}"
fi

# =========================================================================
# Summary
# =========================================================================
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Import complete!${NC}"
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
echo "    2. Review environments/${ENV_NAME}.tfvars"
echo "    3. Set up Vault secrets: make vault-setup ENV=${ENV_NAME}"
echo "    4. Run: make init ENV=${ENV_NAME} && make plan ENV=${ENV_NAME}"
echo ""
