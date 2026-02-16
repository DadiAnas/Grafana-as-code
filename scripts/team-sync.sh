#!/usr/bin/env bash
# =============================================================================
# Team Sync Script (OSS Grafana)
# =============================================================================
# One-way sync: Keycloak → Grafana (Keycloak is the source of truth).
# For every team with external_groups in teams.yaml the script:
#   • ADDs Grafana team members that exist in the mapped Keycloak group(s)
#   • REMOVEs Grafana team members that are no longer in any mapped group
# The script NEVER writes to Keycloak — it is strictly read-only on that side.
#
# This replaces the Enterprise-only grafana_team_external_group resource
# by using the Grafana team members API + Keycloak admin API.
#
# Usage:
#   ./scripts/team-sync.sh <teams-yaml> \
#     --grafana-url=<url> --grafana-auth=<user:pass> \
#     --keycloak-url=<url> --keycloak-realm=<realm> \
#     --keycloak-user=<user> --keycloak-pass=<pass>
#
# Environment variables (alternative to flags):
#   GRAFANA_URL, GRAFANA_AUTH, KEYCLOAK_URL, KEYCLOAK_REALM,
#   KEYCLOAK_USER, KEYCLOAK_PASS
#
# Called automatically by Terraform via local-exec after team creation.
# Can also be run standalone: make team-sync ENV=prod
# =============================================================================
set -euo pipefail

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; DIM='\033[2m'; NC='\033[0m'

# ---- Parse arguments ----
TEAMS_YAML="${1:-}"
shift || true

GRAFANA_URL="${GRAFANA_URL:-}"
GRAFANA_AUTH="${GRAFANA_AUTH:-}"
KEYCLOAK_URL="${KEYCLOAK_URL:-}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-grafana-realm}"
KEYCLOAK_USER="${KEYCLOAK_USER:-}"
KEYCLOAK_PASS="${KEYCLOAK_PASS:-}"
DRY_RUN="${DRY_RUN:-false}"

for arg in "$@"; do
    case "$arg" in
        --grafana-url=*)    GRAFANA_URL="${arg#*=}" ;;
        --grafana-auth=*)   GRAFANA_AUTH="${arg#*=}" ;;
        --keycloak-url=*)   KEYCLOAK_URL="${arg#*=}" ;;
        --keycloak-realm=*) KEYCLOAK_REALM="${arg#*=}" ;;
        --keycloak-user=*)  KEYCLOAK_USER="${arg#*=}" ;;
        --keycloak-pass=*)  KEYCLOAK_PASS="${arg#*=}" ;;
        --dry-run)          DRY_RUN="true" ;;
    esac
done

# ---- Validate ----
if [ -z "$TEAMS_YAML" ] || [ ! -f "$TEAMS_YAML" ]; then
    echo -e "${RED}Error: teams YAML file required as first argument${NC}" >&2
    echo "Usage: $0 <teams.yaml> --grafana-url=... --grafana-auth=... --keycloak-url=... --keycloak-user=... --keycloak-pass=..." >&2
    exit 1
fi
for var_name in GRAFANA_URL GRAFANA_AUTH KEYCLOAK_URL KEYCLOAK_USER KEYCLOAK_PASS; do
    if [ -z "${!var_name}" ]; then
        echo -e "${RED}Error: $var_name is required${NC}" >&2
        exit 1
    fi
done

if [ "$DRY_RUN" = "true" ]; then
    echo -e "${YELLOW}DRY RUN — no changes will be made${NC}"
fi

# ---- Helper: Grafana API ----
grafana_api() {
    local method="$1" path="$2"
    shift 2
    curl -s --connect-timeout 5 --max-time 15 \
        -u "$GRAFANA_AUTH" \
        ${CURRENT_ORG_ID:+-H "X-Grafana-Org-Id: $CURRENT_ORG_ID"} \
        -X "$method" \
        -H "Content-Type: application/json" \
        "${GRAFANA_URL}${path}" "$@"
}

# ---- Helper: Keycloak token ----
keycloak_token() {
    curl -sk --connect-timeout 5 --max-time 15 \
        -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
        -d "client_id=admin-cli" \
        -d "username=${KEYCLOAK_USER}" \
        -d "password=${KEYCLOAK_PASS}" \
        -d "grant_type=password" | python3 -c "import json,sys; print(json.load(sys.stdin)['access_token'])"
}

# ---- Helper: Keycloak API ----
keycloak_api() {
    local path="$1"
    curl -sk --connect-timeout 5 --max-time 15 \
        -H "Authorization: Bearer $KC_TOKEN" \
        "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}${path}"
}

# ---- Main sync logic (all in Python to avoid zsh UUID issues) ----
echo -e "${BLUE}Team Sync${NC} — syncing Keycloak groups → Grafana teams"
echo -e "  Grafana:  ${GRAFANA_URL}"
echo -e "  Keycloak: ${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}"
echo ""

# Get Keycloak token
KC_TOKEN=$(keycloak_token) || { echo -e "${RED}Failed to get Keycloak token${NC}" >&2; exit 1; }

# Export variables for the Python heredoc
export TEAMS_YAML="$TEAMS_YAML"
export GRAFANA_URL GRAFANA_AUTH="$GRAFANA_AUTH" KEYCLOAK_URL KEYCLOAK_REALM
export KC_TOKEN DRY_RUN

# Run the sync via Python to handle JSON/UUIDs safely
python3 << 'PYTHON_SCRIPT'
import json, subprocess, sys, os
from urllib.parse import quote as urlquote

try:
    import yaml
    HAS_YAML = True
except ImportError:
    HAS_YAML = False
    print("Warning: PyYAML not installed, falling back to basic parser", file=sys.stderr)

# ---- Config ----
teams_yaml = os.environ.get("TEAMS_YAML", "")
grafana_url = os.environ.get("GRAFANA_URL", "")
grafana_auth = os.environ.get("GRAFANA_AUTH", "")
keycloak_url = os.environ.get("KEYCLOAK_URL", "")
keycloak_realm = os.environ.get("KEYCLOAK_REALM", "grafana-realm")
kc_token = os.environ.get("KC_TOKEN", "")
dry_run = os.environ.get("DRY_RUN", "false") == "true"

def grafana_get(path, org_id=None):
    headers = ["-u", grafana_auth]
    if org_id:
        headers += ["-H", f"X-Grafana-Org-Id: {org_id}"]
    r = subprocess.run(
        ["curl", "-s", "--connect-timeout", "5", "--max-time", "15"] + headers +
        [f"{grafana_url}{path}"],
        capture_output=True, text=True
    )
    return json.loads(r.stdout) if r.stdout.strip() else None

def grafana_post(path, data, org_id=None):
    headers = ["-u", grafana_auth, "-H", "Content-Type: application/json"]
    if org_id:
        headers += ["-H", f"X-Grafana-Org-Id: {org_id}"]
    r = subprocess.run(
        ["curl", "-s", "--connect-timeout", "5", "--max-time", "15", "-X", "POST"] +
        headers + ["-d", json.dumps(data), f"{grafana_url}{path}"],
        capture_output=True, text=True
    )
    return json.loads(r.stdout) if r.stdout.strip() else None

def grafana_delete(path, org_id=None):
    headers = ["-u", grafana_auth]
    if org_id:
        headers += ["-H", f"X-Grafana-Org-Id: {org_id}"]
    r = subprocess.run(
        ["curl", "-s", "--connect-timeout", "5", "--max-time", "15", "-X", "DELETE"] +
        headers + [f"{grafana_url}{path}"],
        capture_output=True, text=True
    )
    return json.loads(r.stdout) if r.stdout.strip() else None

def keycloak_get(path):
    r = subprocess.run(
        ["curl", "-sk", "--connect-timeout", "5", "--max-time", "15",
         "-H", f"Authorization: Bearer {kc_token}",
         f"{keycloak_url}/admin/realms/{keycloak_realm}{path}"],
        capture_output=True, text=True
    )
    return json.loads(r.stdout) if r.stdout.strip() else None

# ---- Load teams.yaml ----
with open(teams_yaml) as f:
    if HAS_YAML:
        config = yaml.safe_load(f)
    else:
        # Minimal fallback
        import re
        config = json.loads(subprocess.run(
            ["python3", "-c", "import yaml,json,sys; print(json.dumps(yaml.safe_load(sys.stdin)))"],
            input=f.read(), capture_output=True, text=True
        ).stdout)

teams = config.get("teams", [])
teams_with_groups = [t for t in teams if t.get("external_groups")]

if not teams_with_groups:
    print("  No teams with external_groups configured — nothing to sync")
    sys.exit(0)

print(f"  Found {len(teams_with_groups)} team(s) with external_groups mappings\n")

# ---- Get Keycloak groups (name -> id) ----
kc_groups = keycloak_get("/groups?max=200") or []
kc_group_map = {}  # group_name -> group_id
for g in kc_groups:
    kc_group_map[g["name"]] = g["id"]

# ---- Get all Grafana orgs ----
grafana_orgs = grafana_get("/api/orgs") or []
org_name_to_id = {o["name"]: o["id"] for o in grafana_orgs}

# ---- For each org, get teams and users ----
added = 0
removed = 0
skipped = 0
errors = 0

for team in teams_with_groups:
    team_name = team["name"]
    ext_groups = team["external_groups"]
    org_name = team.get("org", "Main Org.")
    org_id = team.get("orgId") or org_name_to_id.get(org_name)

    if not org_id:
        print(f"  \033[0;31m✗\033[0m {team_name}: cannot resolve org '{org_name}'")
        errors += 1
        continue

    # Find the Grafana team ID
    teams_resp = grafana_get(f"/api/teams/search?name={urlquote(team_name)}&perpage=100", org_id=org_id)
    grafana_teams = teams_resp.get("teams", []) if teams_resp else []
    matching = [t for t in grafana_teams if t["name"] == team_name]

    if not matching:
        print(f"  \033[0;31m✗\033[0m {team_name}: not found in Grafana org {org_id}")
        errors += 1
        continue

    grafana_team_id = matching[0]["id"]

    # Get current team members
    current_members = grafana_get(f"/api/teams/{grafana_team_id}/members", org_id=org_id) or []
    current_user_ids = {m["userId"] for m in current_members}

    # Get all Grafana users in this org (needed to resolve username -> userId)
    org_users = grafana_get("/api/org/users", org_id=org_id) or []
    login_to_user = {}
    email_to_user = {}
    for u in org_users:
        login_to_user[u["login"].lower()] = u
        if u.get("email"):
            email_to_user[u["email"].lower()] = u

    # Also get ALL Grafana users (global) so we can find users not yet in this org
    all_grafana_users = []
    page = 1
    while True:
        batch = grafana_get(f"/api/users/search?perpage=200&page={page}") or {}
        users_batch = batch.get("users", [])
        all_grafana_users.extend(users_batch)
        if len(users_batch) < 200:
            break
        page += 1

    global_login_to_user = {}
    global_email_to_user = {}
    for u in all_grafana_users:
        global_login_to_user[u["login"].lower()] = u
        if u.get("email"):
            global_email_to_user[u["email"].lower()] = u

    # Collect desired user IDs from Keycloak groups
    desired_user_ids = set()
    desired_users = {}  # userId -> username (for logging)

    for group_name in ext_groups:
        kc_group_id = kc_group_map.get(group_name)
        if not kc_group_id:
            print(f"  \033[1;33m⚠\033[0m {team_name}: Keycloak group '{group_name}' not found — skipped")
            continue

        # Get Keycloak group members
        kc_members = keycloak_get(f"/groups/{kc_group_id}/members?max=500") or []
        for km in kc_members:
            username = km.get("username", "").lower()
            email = km.get("email", "").lower()

            # First try org-scoped lookup
            grafana_user = login_to_user.get(username) or email_to_user.get(email)

            if not grafana_user:
                # User exists globally but not in this org
                # They must log in via SSO first to get proper org membership & role
                global_user = global_login_to_user.get(username) or global_email_to_user.get(email)
                if global_user:
                    gf_login = global_user["login"]
                    print(f"    \033[1;33m⚠\033[0m {gf_login} exists in Grafana but not in org {org_id} — must log in via SSO to get org mapping")
                    continue
                else:
                    # User doesn't exist in Grafana at all — skip
                    if username or email:
                        print(f"    \033[2m⊘ KC:{username or email} not in Grafana — must log in via SSO first\033[0m")
                    continue

            desired_user_ids.add(grafana_user["userId"])
            desired_users[grafana_user["userId"]] = grafana_user["login"]

    # ---- Sync: Keycloak is source of truth ----
    # Add members present in Keycloak but missing in Grafana team
    # Remove members in Grafana team but no longer in any mapped Keycloak group
    to_add = desired_user_ids - current_user_ids
    to_remove = current_user_ids - desired_user_ids

    if not to_add and not to_remove:
        print(f"  \033[0;32m✓\033[0m {team_name} (org {org_id}): in sync ({len(current_user_ids)} members)")
        skipped += 1
        continue

    print(f"  \033[0;34m↻\033[0m {team_name} (org {org_id}): +{len(to_add)} -{len(to_remove)} members")

    for uid in to_add:
        uname = desired_users.get(uid, f"userId={uid}")
        if dry_run:
            print(f"    [DRY] Would add {uname}")
        else:
            resp = grafana_post(f"/api/teams/{grafana_team_id}/members", {"userId": uid}, org_id=org_id)
            if resp and "added" in str(resp.get("message", "")).lower():
                print(f"    \033[0;32m+\033[0m {uname}")
                added += 1
            else:
                print(f"    \033[0;31m✗\033[0m {uname}: {resp}")
                errors += 1

    for uid in to_remove:
        uname = next((m["login"] for m in current_members if m["userId"] == uid), f"userId={uid}")
        if dry_run:
            print(f"    [DRY] Would remove {uname}")
        else:
            resp = grafana_delete(f"/api/teams/{grafana_team_id}/members/{uid}", org_id=org_id)
            if resp and "removed" in str(resp.get("message", "")).lower():
                print(f"    \033[0;31m-\033[0m {uname}")
                removed += 1
            else:
                print(f"    \033[0;31m✗\033[0m {uname}: {resp}")
                errors += 1

# ---- Summary ----
print()
if dry_run:
    total = sum(1 for t in teams_with_groups if t.get("external_groups"))
    print(f"  Dry run complete — {total} team(s) checked")
else:
    print(f"  Done: +{added} added, -{removed} removed, {skipped} unchanged, {errors} error(s)")
PYTHON_SCRIPT
