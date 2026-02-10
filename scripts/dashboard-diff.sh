#!/bin/bash
# =============================================================================
# DASHBOARD DIFF — Human-readable dashboard change summary
# =============================================================================
# Compares dashboard JSON files and shows a clean summary of what changed
# (panels added/removed/modified, queries changed, etc.) instead of raw JSON.
#
# Usage:
#   bash scripts/dashboard-diff.sh <env-name>                    # vs git HEAD
#   bash scripts/dashboard-diff.sh <env-name> --against=staging  # vs another env
#
# Via Make:
#   make dashboard-diff ENV=prod
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

ENV="${1:?Usage: $0 <env-name> [--against=<env>]}"
AGAINST=""
shift

while [[ $# -gt 0 ]]; do
    case $1 in
        --against=*) AGAINST="${1#*=}"; shift ;;
        *) shift ;;
    esac
done

DASH_DIR="$PROJECT_ROOT/dashboards/${ENV}"

if [ ! -d "$DASH_DIR" ]; then
    echo -e "${RED}Error: dashboards/${ENV}/ not found${NC}"
    exit 1
fi

echo -e "${BOLD}${CYAN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║          Dashboard Diff: ${ENV}"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check for python3 (needed for JSON parsing)
if ! command -v python3 > /dev/null 2>&1; then
    echo -e "${RED}Error: python3 is required for dashboard diff${NC}"
    exit 1
fi

HAS_CHANGES=false

# =========================================================================
# Compare against another environment
# =========================================================================
if [ -n "$AGAINST" ]; then
    AGAINST_DIR="$PROJECT_ROOT/dashboards/${AGAINST}"
    if [ ! -d "$AGAINST_DIR" ]; then
        echo -e "${RED}Error: dashboards/${AGAINST}/ not found${NC}"
        exit 1
    fi

    echo -e "  Comparing: ${BOLD}${ENV}${NC} vs ${BOLD}${AGAINST}${NC}"
    echo ""

    # Find all JSON files in both dirs
    ALL_FILES=$(cd "$PROJECT_ROOT" && {
        find "dashboards/${ENV}" -name "*.json" 2>/dev/null | sed "s|dashboards/${ENV}/||"
        find "dashboards/${AGAINST}" -name "*.json" 2>/dev/null | sed "s|dashboards/${AGAINST}/||"
    } | sort -u)

    while read -r rel_path; do
        [ -z "$rel_path" ] && continue
        FILE_A="$DASH_DIR/$rel_path"
        FILE_B="$AGAINST_DIR/$rel_path"

        if [ ! -f "$FILE_A" ]; then
            echo -e "  ${RED}─${NC} ${rel_path} ${DIM}(only in ${AGAINST})${NC}"
            HAS_CHANGES=true
        elif [ ! -f "$FILE_B" ]; then
            echo -e "  ${GREEN}+${NC} ${rel_path} ${DIM}(only in ${ENV})${NC}"
            HAS_CHANGES=true
        elif ! diff -q "$FILE_A" "$FILE_B" > /dev/null 2>&1; then
            echo -e "  ${YELLOW}~${NC} ${rel_path}"
            # Parse panel differences
            python3 - "$FILE_A" "$FILE_B" << 'PYTHON' 2>/dev/null || true
import json, sys

def load_dashboard(path):
    with open(path) as f:
        data = json.load(f)
    # Handle both wrapped and unwrapped formats
    return data.get('dashboard', data)

a = load_dashboard(sys.argv[1])
b = load_dashboard(sys.argv[2])

# Compare titles
if a.get('title') != b.get('title'):
    print(f"      Title: \"{b.get('title')}\" → \"{a.get('title')}\"")

# Compare panels
panels_a = {p.get('title', f"panel-{p.get('id', '?')}"): p for p in a.get('panels', [])}
panels_b = {p.get('title', f"panel-{p.get('id', '?')}"): p for p in b.get('panels', [])}

added = set(panels_a) - set(panels_b)
removed = set(panels_b) - set(panels_a)
common = set(panels_a) & set(panels_b)

for name in sorted(added):
    ptype = panels_a[name].get('type', '?')
    print(f"      \033[0;32m+ Panel: \"{name}\" ({ptype})\033[0m")

for name in sorted(removed):
    ptype = panels_b[name].get('type', '?')
    print(f"      \033[0;31m- Panel: \"{name}\" ({ptype})\033[0m")

for name in sorted(common):
    pa, pb = panels_a[name], panels_b[name]
    diffs = []
    if pa.get('type') != pb.get('type'):
        diffs.append(f"type: {pb.get('type')} → {pa.get('type')}")
    if pa.get('datasource') != pb.get('datasource'):
        diffs.append("datasource changed")
    if json.dumps(pa.get('targets', []), sort_keys=True) != json.dumps(pb.get('targets', []), sort_keys=True):
        diffs.append("queries modified")
    if pa.get('description') != pb.get('description'):
        diffs.append("description changed")
    if diffs:
        print(f"      \033[1;33m~ Panel: \"{name}\" ({', '.join(diffs)})\033[0m")

# Compare variables
vars_a = {v.get('name', ''): v for v in a.get('templating', {}).get('list', [])}
vars_b = {v.get('name', ''): v for v in b.get('templating', {}).get('list', [])}
added_vars = set(vars_a) - set(vars_b)
removed_vars = set(vars_b) - set(vars_a)
for v in sorted(added_vars):
    print(f"      \033[0;32m+ Variable: ${v}\033[0m")
for v in sorted(removed_vars):
    print(f"      \033[0;31m- Variable: ${v}\033[0m")

# Compare time range
if a.get('time') != b.get('time'):
    print(f"      Time range changed")
PYTHON
            echo ""
            HAS_CHANGES=true
        fi
    done <<< "$ALL_FILES"

# =========================================================================
# Compare against git HEAD
# =========================================================================
else
    echo -e "  Comparing: ${BOLD}${ENV}${NC} dashboards vs ${BOLD}git HEAD${NC}"
    echo ""

    cd "$PROJECT_ROOT"

    # Get list of changed dashboard files from git
    CHANGED_FILES=$(git diff --name-status HEAD -- "dashboards/${ENV}/" 2>/dev/null || true)
    STAGED_FILES=$(git diff --cached --name-status HEAD -- "dashboards/${ENV}/" 2>/dev/null || true)
    UNTRACKED=$(git ls-files --others --exclude-standard -- "dashboards/${ENV}/" 2>/dev/null || true)

    # Process changes
    if [ -n "$CHANGED_FILES" ]; then
        echo "$CHANGED_FILES" | while read -r status filepath; do
            case "$status" in
                A) echo -e "  ${GREEN}+${NC} ${filepath} ${DIM}(added)${NC}"; HAS_CHANGES=true ;;
                D) echo -e "  ${RED}-${NC} ${filepath} ${DIM}(deleted)${NC}"; HAS_CHANGES=true ;;
                M)
                    echo -e "  ${YELLOW}~${NC} ${filepath}"
                    # Get old version from git
                    OLD_CONTENT=$(git show HEAD:"${filepath}" 2>/dev/null || echo "{}")
                    python3 - <(echo "$OLD_CONTENT") "$PROJECT_ROOT/$filepath" << 'PYTHON' 2>/dev/null || true
import json, sys

def load_dashboard(path):
    with open(path) as f:
        data = json.load(f)
    return data.get('dashboard', data)

b = load_dashboard(sys.argv[1])  # old (git HEAD)
a = load_dashboard(sys.argv[2])  # new (working tree)

panels_a = {p.get('title', f"panel-{p.get('id','?')}"): p for p in a.get('panels', [])}
panels_b = {p.get('title', f"panel-{p.get('id','?')}"): p for p in b.get('panels', [])}

for name in sorted(set(panels_a) - set(panels_b)):
    print(f"      \033[0;32m+ Panel: \"{name}\"\033[0m")
for name in sorted(set(panels_b) - set(panels_a)):
    print(f"      \033[0;31m- Panel: \"{name}\"\033[0m")
for name in sorted(set(panels_a) & set(panels_b)):
    if json.dumps(panels_a[name], sort_keys=True) != json.dumps(panels_b[name], sort_keys=True):
        changes = []
        if panels_a[name].get('type') != panels_b[name].get('type'):
            changes.append("type changed")
        if json.dumps(panels_a[name].get('targets',[]),sort_keys=True) != json.dumps(panels_b[name].get('targets',[]),sort_keys=True):
            changes.append("queries modified")
        if not changes:
            changes.append("layout/style")
        print(f"      \033[1;33m~ Panel: \"{name}\" ({', '.join(changes)})\033[0m")
PYTHON
                    echo ""
                    HAS_CHANGES=true
                    ;;
            esac
        done
    fi

    if [ -n "$UNTRACKED" ]; then
        echo "$UNTRACKED" | while read -r filepath; do
            echo -e "  ${GREEN}+${NC} ${filepath} ${DIM}(untracked)${NC}"
            HAS_CHANGES=true
        done
    fi

    if [ -z "$CHANGED_FILES" ] && [ -z "$UNTRACKED" ]; then
        echo -e "  ${GREEN}No dashboard changes detected${NC}"
    fi
fi

echo ""
