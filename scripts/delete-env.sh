#!/bin/bash
# =============================================================================
# DELETE ENVIRONMENT — Cleanup Script
# =============================================================================
# Removes all scaffolded files for an environment.
# This does NOT destroy Terraform-managed infrastructure — use `make destroy`
# for that first!
#
# Usage:
#   bash scripts/delete-env.sh <env-name>
# =============================================================================

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_NAME="${1:-}"

if [ -z "$ENV_NAME" ]; then
    echo -e "${RED}Error: Environment name is required${NC}"
    echo "Usage: $0 <env-name>"
    exit 1
fi

# Protect template environment
if [ "$ENV_NAME" = "myenv" ]; then
    echo -e "${RED}Error: Cannot delete the template environment 'myenv'${NC}"
    echo "This is the reference template for creating new environments."
    exit 1
fi

# Check if environment exists
ENV_EXISTS=false
[ -f "$PROJECT_ROOT/environments/${ENV_NAME}.tfvars" ] && ENV_EXISTS=true
[ -f "$PROJECT_ROOT/backends/${ENV_NAME}.tfbackend" ] && ENV_EXISTS=true
[ -d "$PROJECT_ROOT/config/${ENV_NAME}" ] && ENV_EXISTS=true
[ -d "$PROJECT_ROOT/dashboards/${ENV_NAME}" ] && ENV_EXISTS=true

if [ "$ENV_EXISTS" = false ]; then
    echo -e "${RED}Error: Environment '${ENV_NAME}' does not exist${NC}"
    exit 1
fi

echo -e "${BOLD}${YELLOW}⚠️  This will delete all scaffolding files for '${ENV_NAME}'${NC}"
echo ""
echo "Files that will be removed:"
[ -f "$PROJECT_ROOT/environments/${ENV_NAME}.tfvars" ] && echo "  - environments/${ENV_NAME}.tfvars"
[ -f "$PROJECT_ROOT/backends/${ENV_NAME}.tfbackend" ] && echo "  - backends/${ENV_NAME}.tfbackend"
[ -d "$PROJECT_ROOT/config/${ENV_NAME}" ] && echo "  - config/${ENV_NAME}/ ($(find "$PROJECT_ROOT/config/${ENV_NAME}" -type f | wc -l) files)"
[ -d "$PROJECT_ROOT/dashboards/${ENV_NAME}" ] && echo "  - dashboards/${ENV_NAME}/ ($(find "$PROJECT_ROOT/dashboards/${ENV_NAME}" -type f | wc -l) files)"
[ -f "$PROJECT_ROOT/tfplan-${ENV_NAME}" ] && echo "  - tfplan-${ENV_NAME}"
echo ""
echo -e "${RED}⚠️  Make sure you have run 'make destroy ENV=${ENV_NAME}' first if infrastructure was applied!${NC}"
echo ""
read -p "Type '${ENV_NAME}' to confirm deletion: " confirm

if [ "$confirm" != "$ENV_NAME" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""

[ -f "$PROJECT_ROOT/environments/${ENV_NAME}.tfvars" ] && rm -f "$PROJECT_ROOT/environments/${ENV_NAME}.tfvars" && echo -e "${GREEN}✓${NC} Removed environments/${ENV_NAME}.tfvars"
[ -f "$PROJECT_ROOT/backends/${ENV_NAME}.tfbackend" ] && rm -f "$PROJECT_ROOT/backends/${ENV_NAME}.tfbackend" && echo -e "${GREEN}✓${NC} Removed backends/${ENV_NAME}.tfbackend"
[ -d "$PROJECT_ROOT/config/${ENV_NAME}" ] && rm -rf "$PROJECT_ROOT/config/${ENV_NAME}" && echo -e "${GREEN}✓${NC} Removed config/${ENV_NAME}/"
[ -d "$PROJECT_ROOT/dashboards/${ENV_NAME}" ] && rm -rf "$PROJECT_ROOT/dashboards/${ENV_NAME}" && echo -e "${GREEN}✓${NC} Removed dashboards/${ENV_NAME}/"
[ -f "$PROJECT_ROOT/tfplan-${ENV_NAME}" ] && rm -f "$PROJECT_ROOT/tfplan-${ENV_NAME}" && echo -e "${GREEN}✓${NC} Removed tfplan-${ENV_NAME}"

echo ""
echo -e "${GREEN}✅ Environment '${ENV_NAME}' deleted.${NC}"
