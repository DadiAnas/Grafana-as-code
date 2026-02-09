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
#   bash scripts/delete-env.sh <env-name> --force  (skip confirmation)
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
ENV_NAME="${1:-}"
FORCE=false

# Parse flags
for arg in "$@"; do
    case "$arg" in
        --force|-f) FORCE=true ;;
    esac
done

if [ -z "$ENV_NAME" ] || [[ "$ENV_NAME" == --* ]]; then
    echo -e "${RED}Error: Environment name is required${NC}"
    echo ""
    echo "Usage: $0 <env-name>"
    echo "       $0 <env-name> --force  (skip confirmation)"
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

# -------------------------------------------------------------------------
# Show what will be deleted
# -------------------------------------------------------------------------
echo ""
echo -e "${BOLD}${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${RED}║    ⚠️  DELETE ENVIRONMENT: ${ENV_NAME}${NC}"
echo -e "${BOLD}${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}The following files will be ${RED}permanently deleted${NC}${BOLD}:${NC}"
echo ""

TOTAL_FILES=0
if [ -f "$PROJECT_ROOT/environments/${ENV_NAME}.tfvars" ]; then
    echo -e "  ${RED}✗${NC} environments/${ENV_NAME}.tfvars"
    TOTAL_FILES=$((TOTAL_FILES + 1))
fi
if [ -f "$PROJECT_ROOT/backends/${ENV_NAME}.tfbackend" ]; then
    echo -e "  ${RED}✗${NC} backends/${ENV_NAME}.tfbackend"
    TOTAL_FILES=$((TOTAL_FILES + 1))
fi
if [ -d "$PROJECT_ROOT/config/${ENV_NAME}" ]; then
    CONFIG_COUNT=$(find "$PROJECT_ROOT/config/${ENV_NAME}" -type f | wc -l)
    echo -e "  ${RED}✗${NC} config/${ENV_NAME}/ ${DIM}(${CONFIG_COUNT} files)${NC}"
    TOTAL_FILES=$((TOTAL_FILES + CONFIG_COUNT))
fi
if [ -d "$PROJECT_ROOT/dashboards/${ENV_NAME}" ]; then
    DASH_COUNT=$(find "$PROJECT_ROOT/dashboards/${ENV_NAME}" -type f | wc -l)
    JSON_COUNT=$(find "$PROJECT_ROOT/dashboards/${ENV_NAME}" -name '*.json' 2>/dev/null | wc -l)
    echo -e "  ${RED}✗${NC} dashboards/${ENV_NAME}/ ${DIM}(${DASH_COUNT} files, ${JSON_COUNT} dashboards)${NC}"
    TOTAL_FILES=$((TOTAL_FILES + DASH_COUNT))
fi
if [ -f "$PROJECT_ROOT/tfplan-${ENV_NAME}" ]; then
    echo -e "  ${RED}✗${NC} tfplan-${ENV_NAME}"
    TOTAL_FILES=$((TOTAL_FILES + 1))
fi

echo ""
echo -e "  ${BOLD}Total: ${TOTAL_FILES} file(s) will be deleted${NC}"
echo ""

# -------------------------------------------------------------------------
# Warning about infrastructure
# -------------------------------------------------------------------------
echo -e "${YELLOW}${BOLD}⚠️  IMPORTANT:${NC}"
echo -e "${YELLOW}   This only deletes local scaffolding files.${NC}"
echo -e "${YELLOW}   If you have applied Terraform, the infrastructure still exists!${NC}"
echo -e "${YELLOW}   Run ${BOLD}make destroy ENV=${ENV_NAME}${NC}${YELLOW} first to tear down resources.${NC}"
echo ""

# -------------------------------------------------------------------------
# Confirmation
# -------------------------------------------------------------------------
if [ "$FORCE" = true ]; then
    echo -e "${DIM}Skipping confirmation (--force)${NC}"
else
    echo -e "${BOLD}To confirm deletion, type the environment name: ${RED}${ENV_NAME}${NC}"
    echo ""
    read -p "  ▸ " confirm

    if [ "$confirm" != "$ENV_NAME" ]; then
        echo ""
        echo -e "${GREEN}Cancelled.${NC} No files were deleted."
        exit 0
    fi
fi

echo ""

# -------------------------------------------------------------------------
# Delete files
# -------------------------------------------------------------------------
[ -f "$PROJECT_ROOT/environments/${ENV_NAME}.tfvars" ] && rm -f "$PROJECT_ROOT/environments/${ENV_NAME}.tfvars" && echo -e "  ${GREEN}✓${NC} Removed environments/${ENV_NAME}.tfvars"
[ -f "$PROJECT_ROOT/backends/${ENV_NAME}.tfbackend" ] && rm -f "$PROJECT_ROOT/backends/${ENV_NAME}.tfbackend" && echo -e "  ${GREEN}✓${NC} Removed backends/${ENV_NAME}.tfbackend"
[ -d "$PROJECT_ROOT/config/${ENV_NAME}" ] && rm -rf "$PROJECT_ROOT/config/${ENV_NAME}" && echo -e "  ${GREEN}✓${NC} Removed config/${ENV_NAME}/"
[ -d "$PROJECT_ROOT/dashboards/${ENV_NAME}" ] && rm -rf "$PROJECT_ROOT/dashboards/${ENV_NAME}" && echo -e "  ${GREEN}✓${NC} Removed dashboards/${ENV_NAME}/"
[ -f "$PROJECT_ROOT/tfplan-${ENV_NAME}" ] && rm -f "$PROJECT_ROOT/tfplan-${ENV_NAME}" && echo -e "  ${GREEN}✓${NC} Removed tfplan-${ENV_NAME}"

echo ""
echo -e "${GREEN}${BOLD}✅ Environment '${ENV_NAME}' has been deleted.${NC}"
echo ""
