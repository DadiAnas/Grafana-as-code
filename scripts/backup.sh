#!/bin/bash
# =============================================================================
# BACKUP — Snapshot current Grafana state via API before destructive operations
# =============================================================================
# Exports dashboards, datasources, and alert config from Grafana to a
# timestamped backup directory. Useful as a safety net before `terraform apply`.
#
# Usage:
#   bash scripts/backup.sh <env-name>
#   make backup ENV=prod
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV="${1:?Usage: $0 <env-name>}"

# Read Grafana URL from tfvars
TFVARS_FILE="$PROJECT_ROOT/environments/${ENV}.tfvars"
if [ ! -f "$TFVARS_FILE" ]; then
    echo -e "${RED}Error: environments/${ENV}.tfvars not found${NC}"
    exit 1
fi

GRAFANA_URL=$(grep -E '^grafana_url\s*=' "$TFVARS_FILE" | sed 's/.*=\s*"\(.*\)"/\1/' | tr -d ' ')
AUTH="${GRAFANA_AUTH:-admin:admin}"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$PROJECT_ROOT/backups/${ENV}/${TIMESTAMP}"
mkdir -p "$BACKUP_DIR"

echo -e "${BOLD}${CYAN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║          Backup: ${ENV} → backups/${ENV}/${TIMESTAMP}"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# API helper
grafana_api() {
    local endpoint="$1"
    if [[ "$AUTH" == *":"* ]]; then
        curl -sf -u "${AUTH}" "${GRAFANA_URL}${endpoint}" 2>/dev/null
    else
        curl -sf -H "Authorization: Bearer ${AUTH}" "${GRAFANA_URL}${endpoint}" 2>/dev/null
    fi
}

# Test connection
HEALTH=$(grafana_api "/api/health" || echo "FAILED")
if ! echo "$HEALTH" | grep -q "ok"; then
    echo -e "${RED}Cannot connect to Grafana at ${GRAFANA_URL}${NC}"
    echo "  Set GRAFANA_AUTH env var (e.g., export GRAFANA_AUTH=admin:admin)"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Connected to ${GRAFANA_URL}"
echo ""

TOTAL=0

# 1. Datasources
echo -e "${BLUE}[1/5]${NC} Backing up datasources..."
DS_JSON=$(grafana_api "/api/datasources" || echo "[]")
echo "$DS_JSON" > "$BACKUP_DIR/datasources.json"
DS_COUNT=$(echo "$DS_JSON" | grep -o '"id"' | wc -l)
echo -e "  ${GREEN}✓${NC} ${DS_COUNT} datasource(s)"
TOTAL=$((TOTAL + DS_COUNT))

# 2. Folders
echo -e "${BLUE}[2/5]${NC} Backing up folders..."
FOLDERS_JSON=$(grafana_api "/api/folders?limit=1000" || echo "[]")
echo "$FOLDERS_JSON" > "$BACKUP_DIR/folders.json"
FOLDER_COUNT=$(echo "$FOLDERS_JSON" | grep -o '"uid"' | wc -l)
echo -e "  ${GREEN}✓${NC} ${FOLDER_COUNT} folder(s)"
TOTAL=$((TOTAL + FOLDER_COUNT))

# 3. Dashboards
echo -e "${BLUE}[3/5]${NC} Backing up dashboards..."
mkdir -p "$BACKUP_DIR/dashboards"
SEARCH_JSON=$(grafana_api "/api/search?type=dash-db&limit=5000" || echo "[]")
DASH_COUNT=0

echo "$SEARCH_JSON" | python3 -c "
import json, sys
for d in json.load(sys.stdin):
    print(d.get('uid', ''))
" 2>/dev/null | while read -r uid; do
    [ -z "$uid" ] && continue
    DASH=$(grafana_api "/api/dashboards/uid/${uid}" || echo "")
    if [ -n "$DASH" ]; then
        TITLE=$(echo "$DASH" | python3 -c "import json,sys; print(json.load(sys.stdin).get('dashboard',{}).get('title','unknown'))" 2>/dev/null || echo "$uid")
        SAFE_TITLE=$(echo "$TITLE" | sed 's/[^a-zA-Z0-9 _-]//g')
        echo "$DASH" > "$BACKUP_DIR/dashboards/${SAFE_TITLE}.json"
    fi
done
DASH_FILES=$(find "$BACKUP_DIR/dashboards" -name "*.json" 2>/dev/null | wc -l)
echo -e "  ${GREEN}✓${NC} ${DASH_FILES} dashboard(s)"
TOTAL=$((TOTAL + DASH_FILES))

# 4. Alert rules
echo -e "${BLUE}[4/5]${NC} Backing up alert configuration..."
grafana_api "/api/v1/provisioning/alert-rules" > "$BACKUP_DIR/alert_rules.json" 2>/dev/null || echo "[]" > "$BACKUP_DIR/alert_rules.json"
grafana_api "/api/v1/provisioning/contact-points" > "$BACKUP_DIR/contact_points.json" 2>/dev/null || echo "[]" > "$BACKUP_DIR/contact_points.json"
grafana_api "/api/v1/provisioning/policies" > "$BACKUP_DIR/notification_policies.json" 2>/dev/null || echo "{}" > "$BACKUP_DIR/notification_policies.json"
echo -e "  ${GREEN}✓${NC} Alert rules, contact points, notification policies"
TOTAL=$((TOTAL + 3))

# 5. Organizations & Teams
echo -e "${BLUE}[5/5]${NC} Backing up organizations & teams..."
grafana_api "/api/orgs" > "$BACKUP_DIR/organizations.json" 2>/dev/null || echo "[]" > "$BACKUP_DIR/organizations.json"
grafana_api "/api/teams/search?perpage=1000" > "$BACKUP_DIR/teams.json" 2>/dev/null || echo '{"teams":[]}' > "$BACKUP_DIR/teams.json"
echo -e "  ${GREEN}✓${NC} Organizations & teams"
TOTAL=$((TOTAL + 2))

# Summary
BACKUP_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ Backup complete!${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Location:  backups/${ENV}/${TIMESTAMP}/"
echo "  Size:      ${BACKUP_SIZE}"
echo "  Items:     ${TOTAL} resource(s)"
echo ""
echo "  Files:"
ls -1 "$BACKUP_DIR" | sed 's/^/    /'
echo ""
echo "  To restore, use the Grafana API or re-import:"
echo "    bash scripts/import-from-grafana.sh ${ENV}-restored --grafana-url=${GRAFANA_URL} --auth=\$AUTH"
echo ""
