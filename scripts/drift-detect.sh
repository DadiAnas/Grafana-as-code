#!/bin/bash
# =============================================================================
# DRIFT DETECTION — Detect out-of-band changes to Grafana
# =============================================================================
# Runs terraform plan in check mode and reports if any resources have been
# modified outside of Terraform (manual UI changes, API calls, etc.).
#
# Usage:
#   bash scripts/drift-detect.sh <env-name>
#   make drift ENV=staging
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

echo -e "${BOLD}${CYAN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║          Drift Detection: ${ENV}"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Validate environment exists
if [ ! -f "$PROJECT_ROOT/environments/${ENV}.tfvars" ]; then
    echo -e "${RED}Error: Environment '${ENV}' not found${NC}"
    echo "  Missing: environments/${ENV}.tfvars"
    exit 1
fi

# Run terraform plan in detailed-exitcode mode
# Exit code 0 = no changes, 1 = error, 2 = changes detected
echo -e "${BLUE}Running terraform plan...${NC}"
echo ""

PLAN_OUTPUT=$(cd "$PROJECT_ROOT" && terraform plan \
    -var-file="environments/${ENV}.tfvars" \
    -var="environment=${ENV}" \
    -detailed-exitcode \
    -no-color \
    -compact-warnings 2>&1) || PLAN_EXIT=$?

PLAN_EXIT=${PLAN_EXIT:-0}

case $PLAN_EXIT in
    0)
        echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  ✅ No drift detected — Grafana matches Terraform state${NC}"
        echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
        exit 0
        ;;
    2)
        echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║  ⚠️  DRIFT DETECTED — Resources differ from Terraform state${NC}"
        echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
        echo ""

        # Parse the plan output for changes
        ADDS=$(echo "$PLAN_OUTPUT" | grep -c '# .* will be created' 2>/dev/null || echo 0)
        CHANGES=$(echo "$PLAN_OUTPUT" | grep -c '# .* will be updated' 2>/dev/null || echo 0)
        DESTROYS=$(echo "$PLAN_OUTPUT" | grep -c '# .* will be destroyed' 2>/dev/null || echo 0)

        echo "  Summary:"
        [ "$ADDS" -gt 0 ] && echo -e "    ${GREEN}+ ${ADDS} to add${NC}"
        [ "$CHANGES" -gt 0 ] && echo -e "    ${YELLOW}~ ${CHANGES} to change${NC}"
        [ "$DESTROYS" -gt 0 ] && echo -e "    ${RED}- ${DESTROYS} to destroy${NC}"
        echo ""

        # Show changed resources
        echo "  Changed resources:"
        echo "$PLAN_OUTPUT" | grep '^  # ' | sed 's/^  # /    /' | head -20
        echo ""

        echo "  To see full details:"
        echo "    make plan ENV=${ENV}"
        echo ""
        echo "  To reconcile (apply Terraform state):"
        echo "    make apply ENV=${ENV}"
        echo ""
        exit 2
        ;;
    *)
        echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║  ❌ Error running drift detection${NC}"
        echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "$PLAN_OUTPUT" | tail -20
        exit 1
        ;;
esac
