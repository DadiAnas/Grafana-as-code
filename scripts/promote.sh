#!/bin/bash
# =============================================================================
# PROMOTE ENVIRONMENT — Copy/diff configs between environments
# =============================================================================
# Promotes configuration from one environment to another. Useful for
# moving tested changes from staging → production.
#
# Usage:
#   bash scripts/promote.sh <from-env> <to-env>
#   bash scripts/promote.sh staging prod               # copy staging to prod
#   bash scripts/promote.sh staging prod --diff-only    # just show differences
#
# Via Make:
#   make promote FROM=staging TO=prod
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

FROM="${1:?Usage: $0 <from-env> <to-env> [--diff-only]}"
TO="${2:?Usage: $0 <from-env> <to-env> [--diff-only]}"
DIFF_ONLY=false

shift 2
while [[ $# -gt 0 ]]; do
    case $1 in
        --diff-only) DIFF_ONLY=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

FROM_CONFIG="$PROJECT_ROOT/config/${FROM}"
TO_CONFIG="$PROJECT_ROOT/config/${TO}"
FROM_DASHBOARDS="$PROJECT_ROOT/dashboards/${FROM}"
TO_DASHBOARDS="$PROJECT_ROOT/dashboards/${TO}"

echo -e "${BOLD}${CYAN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║          Promote: ${FROM} → ${TO}"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Validate source exists
if [ ! -d "$FROM_CONFIG" ]; then
    echo -e "${RED}Error: Source environment '${FROM}' not found${NC}"
    echo "  Missing: config/${FROM}/"
    exit 1
fi

# =========================================================================
# Show diff between environments
# =========================================================================
echo -e "${BLUE}Configuration differences:${NC}"
echo ""

HAS_DIFF=false

# Compare config files
for file in $(find "$FROM_CONFIG" -type f -name "*.yaml" | sort); do
    REL_PATH="${file#$FROM_CONFIG/}"
    TO_FILE="$TO_CONFIG/$REL_PATH"

    if [ ! -f "$TO_FILE" ]; then
        echo -e "  ${GREEN}+ ${REL_PATH}${NC} (new — only in ${FROM})"
        HAS_DIFF=true
    elif ! diff -q "$file" "$TO_FILE" > /dev/null 2>&1; then
        echo -e "  ${YELLOW}~ ${REL_PATH}${NC} (modified)"
        # Show compact diff
        diff --color=always -u "$TO_FILE" "$file" 2>/dev/null | head -30 | sed 's/^/    /'
        echo ""
        HAS_DIFF=true
    fi
done

# Check for files only in target
if [ -d "$TO_CONFIG" ]; then
    for file in $(find "$TO_CONFIG" -type f -name "*.yaml" | sort); do
        REL_PATH="${file#$TO_CONFIG/}"
        FROM_FILE="$FROM_CONFIG/$REL_PATH"
        if [ ! -f "$FROM_FILE" ]; then
            echo -e "  ${RED}- ${REL_PATH}${NC} (only in ${TO}, would be kept)"
            HAS_DIFF=true
        fi
    done
fi

# Compare dashboards
if [ -d "$FROM_DASHBOARDS" ]; then
    echo ""
    echo -e "${BLUE}Dashboard differences:${NC}"
    echo ""
    for file in $(find "$FROM_DASHBOARDS" -type f -name "*.json" | sort); do
        REL_PATH="${file#$FROM_DASHBOARDS/}"
        TO_FILE="$TO_DASHBOARDS/$REL_PATH"
        if [ ! -f "$TO_FILE" ]; then
            echo -e "  ${GREEN}+ ${REL_PATH}${NC} (new)"
            HAS_DIFF=true
        elif ! diff -q "$file" "$TO_FILE" > /dev/null 2>&1; then
            echo -e "  ${YELLOW}~ ${REL_PATH}${NC} (modified)"
            HAS_DIFF=true
        fi
    done
fi

if [ "$HAS_DIFF" = false ]; then
    echo -e "  ${GREEN}No differences found — environments are in sync${NC}"
    exit 0
fi

# Diff-only mode stops here
if [ "$DIFF_ONLY" = true ]; then
    echo ""
    echo -e "${DIM}  (--diff-only mode, no changes applied)${NC}"
    exit 0
fi

# =========================================================================
# Confirm promotion
# =========================================================================
echo ""
echo -e "${YELLOW}⚠  This will overwrite config/${TO}/ with config/${FROM}/${NC}"
echo -e "   dashboards/${TO}/ will also be synced from dashboards/${FROM}/"
echo ""
read -p "  Continue? [y/N] " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${DIM}  Aborted.${NC}"
    exit 0
fi

# =========================================================================
# Perform promotion
# =========================================================================
echo ""
echo -e "${BLUE}Promoting configuration...${NC}"

# Create target directories
mkdir -p "$TO_CONFIG/alerting"
mkdir -p "$TO_DASHBOARDS"

# Copy config files (preserve target-only files)
COPIED=0
for file in $(find "$FROM_CONFIG" -type f -name "*.yaml" | sort); do
    REL_PATH="${file#$FROM_CONFIG/}"
    TO_FILE="$TO_CONFIG/$REL_PATH"
    mkdir -p "$(dirname "$TO_FILE")"
    cp "$file" "$TO_FILE"
    echo -e "  ${GREEN}✓${NC} config/${TO}/${REL_PATH}"
    COPIED=$((COPIED + 1))
done

# Copy dashboards
DASH_COPIED=0
if [ -d "$FROM_DASHBOARDS" ]; then
    for file in $(find "$FROM_DASHBOARDS" -type f -name "*.json" | sort); do
        REL_PATH="${file#$FROM_DASHBOARDS/}"
        TO_FILE="$TO_DASHBOARDS/$REL_PATH"
        mkdir -p "$(dirname "$TO_FILE")"
        cp "$file" "$TO_FILE"
        DASH_COPIED=$((DASH_COPIED + 1))
    done
    echo -e "  ${GREEN}✓${NC} ${DASH_COPIED} dashboard(s) copied"
fi

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Promotion complete: ${FROM} → ${TO}${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Config files: ${COPIED}"
echo "  Dashboards:   ${DASH_COPIED}"
echo ""
echo "  Next steps:"
echo "    1. Review the promoted configs: git diff config/${TO}/"
echo "    2. Adjust env-specific values (URLs, credentials, etc.)"
echo "    3. Plan & apply:"
echo "       make plan  ENV=${TO}"
echo "       make apply ENV=${TO}"
echo ""
