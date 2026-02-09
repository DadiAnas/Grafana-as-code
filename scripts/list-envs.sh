#!/bin/bash
# =============================================================================
# LIST ENVIRONMENTS — Show all configured environments
# =============================================================================
# Usage: bash scripts/list-envs.sh
# =============================================================================

set -euo pipefail

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "${BOLD}${CYAN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                  Configured Environments                     ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Discover environments from config/ directories (excluding shared)
ENVS=$(find "$PROJECT_ROOT/config" -maxdepth 1 -mindepth 1 -type d ! -name 'shared' -printf '%f\n' | sort)

if [ -z "$ENVS" ]; then
    echo -e "  ${YELLOW}No environments found.${NC}"
    echo ""
    echo -e "  Create one with: ${BOLD}make new-env NAME=<name>${NC}"
    exit 0
fi

COUNT=0
while IFS= read -r env; do
    [ -z "$env" ] && continue
    COUNT=$((COUNT + 1))

    # Check completeness
    HAS_TFVARS="❌"
    HAS_BACKEND="❌"
    HAS_CONFIG="❌"
    HAS_DASHBOARDS="❌"
    GRAFANA_URL="${DIM}not set${NC}"

    [ -f "$PROJECT_ROOT/environments/${env}.tfvars" ] && HAS_TFVARS="${GREEN}✓${NC}"
    [ -f "$PROJECT_ROOT/backends/${env}.tfbackend" ] && HAS_BACKEND="${GREEN}✓${NC}"
    [ -d "$PROJECT_ROOT/config/${env}" ] && HAS_CONFIG="${GREEN}✓${NC}"
    [ -d "$PROJECT_ROOT/dashboards/${env}" ] && HAS_DASHBOARDS="${GREEN}✓${NC}"

    # Extract Grafana URL from tfvars
    if [ -f "$PROJECT_ROOT/environments/${env}.tfvars" ]; then
        URL=$(grep -E '^\s*grafana_url\s*=' "$PROJECT_ROOT/environments/${env}.tfvars" | sed 's/.*=\s*//;s/"//g;s/\s*$//' | head -1)
        [ -n "$URL" ] && GRAFANA_URL="$URL"
    fi

    # Count dashboards
    DASHBOARD_COUNT=0
    if [ -d "$PROJECT_ROOT/dashboards/${env}" ]; then
        DASHBOARD_COUNT=$(find "$PROJECT_ROOT/dashboards/${env}" -name '*.json' | wc -l)
    fi

    # Count config files
    CONFIG_COUNT=0
    if [ -d "$PROJECT_ROOT/config/${env}" ]; then
        CONFIG_COUNT=$(find "$PROJECT_ROOT/config/${env}" -name '*.yaml' | wc -l)
    fi

    # Template marker
    TEMPLATE_LABEL=""
    [ "$env" = "myenv" ] && TEMPLATE_LABEL=" ${DIM}(template)${NC}"

    echo -e "  ${BOLD}${BLUE}${env}${NC}${TEMPLATE_LABEL}"
    echo -e "    Grafana URL:       ${GRAFANA_URL}"
    echo -e "    tfvars:     ${HAS_TFVARS}   backend:    ${HAS_BACKEND}   config:     ${HAS_CONFIG}   dashboards: ${HAS_DASHBOARDS}"
    echo -e "    Config files: ${CONFIG_COUNT}     Dashboard JSON files: ${DASHBOARD_COUNT}"
    echo ""
done <<< "$ENVS"

echo -e "  ${DIM}────────────────────────────────────────────────${NC}"
echo -e "  ${BOLD}Total: ${COUNT} environment(s)${NC}"
echo ""
echo -e "  ${DIM}Commands:${NC}"
echo -e "    Create new:  ${BOLD}make new-env NAME=<name>${NC}"
echo -e "    Delete:      ${BOLD}make delete-env NAME=<name>${NC}"
echo -e "    Deploy:      ${BOLD}make init ENV=<name> && make plan ENV=<name>${NC}"
echo ""
