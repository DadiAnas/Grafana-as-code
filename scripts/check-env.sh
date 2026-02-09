#!/bin/bash
# =============================================================================
# CHECK ENVIRONMENT — Validate environment is ready for deployment
# =============================================================================
# Verifies all required files exist, configs are valid YAML, and
# optional Vault connectivity if VAULT_ADDR is set.
#
# Usage: bash scripts/check-env.sh <env-name>
# =============================================================================

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_NAME="${1:-}"
ERRORS=0
WARNINGS=0

if [ -z "$ENV_NAME" ]; then
    echo -e "${RED}Error: Environment name is required${NC}"
    echo "Usage: $0 <env-name>"
    exit 1
fi

echo -e "${BOLD}${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║          Environment Check: ${ENV_NAME}"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

pass() { echo -e "  ${GREEN}✅ PASS${NC}  $1"; }
fail() { echo -e "  ${RED}❌ FAIL${NC}  $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo -e "  ${YELLOW}⚠️  WARN${NC}  $1"; WARNINGS=$((WARNINGS + 1)); }
info() { echo -e "  ${BLUE}ℹ️  INFO${NC}  $1"; }

# -------------------------------------------------------------------------
# 1. Required files
# -------------------------------------------------------------------------
echo -e "${BOLD}── Required Files ──${NC}"

if [ -f "$PROJECT_ROOT/environments/${ENV_NAME}.tfvars" ]; then
    pass "environments/${ENV_NAME}.tfvars"
else
    fail "environments/${ENV_NAME}.tfvars is missing"
fi

if [ -d "$PROJECT_ROOT/config/${ENV_NAME}" ]; then
    pass "config/${ENV_NAME}/ directory"
else
    fail "config/${ENV_NAME}/ directory is missing"
fi

if [ -d "$PROJECT_ROOT/dashboards/${ENV_NAME}" ]; then
    pass "dashboards/${ENV_NAME}/ directory"
else
    fail "dashboards/${ENV_NAME}/ directory is missing"
fi

echo ""

# -------------------------------------------------------------------------
# 2. Optional files
# -------------------------------------------------------------------------
echo -e "${BOLD}── Optional Files ──${NC}"

if [ -f "$PROJECT_ROOT/backends/${ENV_NAME}.tfbackend" ]; then
    pass "backends/${ENV_NAME}.tfbackend"
else
    info "backends/${ENV_NAME}.tfbackend not found (using local state)"
fi

echo ""

# -------------------------------------------------------------------------
# 3. Configuration YAML files
# -------------------------------------------------------------------------
echo -e "${BOLD}── Configuration Files ──${NC}"

EXPECTED_CONFIG_FILES=(
    "organizations.yaml"
    "datasources.yaml"
    "folders.yaml"
    "teams.yaml"
    "service_accounts.yaml"
    "sso.yaml"
    "keycloak.yaml"
    "alerting/alert_rules.yaml"
    "alerting/contact_points.yaml"
    "alerting/notification_policies.yaml"
)

for cfg in "${EXPECTED_CONFIG_FILES[@]}"; do
    if [ -f "$PROJECT_ROOT/config/${ENV_NAME}/${cfg}" ]; then
        pass "config/${ENV_NAME}/${cfg}"
    else
        warn "config/${ENV_NAME}/${cfg} is missing (shared config will apply)"
    fi
done

echo ""

# -------------------------------------------------------------------------
# 4. Shared config sanity check
# -------------------------------------------------------------------------
echo -e "${BOLD}── Shared Configuration ──${NC}"

for cfg in "${EXPECTED_CONFIG_FILES[@]}"; do
    if [ -f "$PROJECT_ROOT/config/shared/${cfg}" ]; then
        pass "config/shared/${cfg}"
    else
        fail "config/shared/${cfg} is missing!"
    fi
done

echo ""

# -------------------------------------------------------------------------
# 5. Environment variables in tfvars
# -------------------------------------------------------------------------
echo -e "${BOLD}── Variables Check ──${NC}"

if [ -f "$PROJECT_ROOT/environments/${ENV_NAME}.tfvars" ]; then
    TFVARS_FILE="$PROJECT_ROOT/environments/${ENV_NAME}.tfvars"

    # Check grafana_url is set
    if grep -qE '^\s*grafana_url\s*=' "$TFVARS_FILE"; then
        URL=$(grep -E '^\s*grafana_url\s*=' "$TFVARS_FILE" | sed 's/.*=\s*//;s/"//g;s/\s*$//' | head -1)
        pass "grafana_url = ${URL}"
    else
        fail "grafana_url is not set in tfvars"
    fi

    # Check environment matches
    if grep -qE '^\s*environment\s*=' "$TFVARS_FILE"; then
        ENV_VAL=$(grep -E '^\s*environment\s*=' "$TFVARS_FILE" | sed 's/.*=\s*//;s/"//g;s/\s*$//' | head -1)
        if [ "$ENV_VAL" = "$ENV_NAME" ]; then
            pass "environment = ${ENV_VAL} (matches)"
        else
            fail "environment = ${ENV_VAL} (expected '${ENV_NAME}')"
        fi
    else
        fail "environment is not set in tfvars"
    fi

    # Check vault_address
    if grep -qE '^\s*vault_address\s*=' "$TFVARS_FILE"; then
        pass "vault_address is configured"
    else
        warn "vault_address is not set"
    fi
fi

echo ""

# -------------------------------------------------------------------------
# 6. Dashboard structure
# -------------------------------------------------------------------------
echo -e "${BOLD}── Dashboard Structure ──${NC}"

if [ -d "$PROJECT_ROOT/dashboards/${ENV_NAME}" ]; then
    ORG_DIRS=$(find "$PROJECT_ROOT/dashboards/${ENV_NAME}" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort)
    if [ -n "$ORG_DIRS" ]; then
        while IFS= read -r org; do
            JSON_COUNT=$(find "$PROJECT_ROOT/dashboards/${ENV_NAME}/${org}" -name '*.json' 2>/dev/null | wc -l)
            info "dashboards/${ENV_NAME}/${org}/ (${JSON_COUNT} dashboard files)"
        done <<< "$ORG_DIRS"
    else
        warn "No organization subdirectories in dashboards/${ENV_NAME}/"
    fi
fi

if [ -d "$PROJECT_ROOT/dashboards/shared" ]; then
    SHARED_JSON=$(find "$PROJECT_ROOT/dashboards/shared" -name '*.json' | wc -l)
    info "dashboards/shared/ (${SHARED_JSON} shared dashboard files)"
fi

echo ""

# -------------------------------------------------------------------------
# 7. Vault connectivity (optional)
# -------------------------------------------------------------------------
echo -e "${BOLD}── Vault Connectivity ──${NC}"

if [ -n "${VAULT_ADDR:-}" ]; then
    if command -v vault &>/dev/null; then
        if vault status &>/dev/null; then
            pass "Vault is reachable at ${VAULT_ADDR}"
            if vault kv list "grafana/${ENV_NAME}/" &>/dev/null; then
                pass "Vault secrets exist at grafana/${ENV_NAME}/"
            else
                warn "No secrets found at grafana/${ENV_NAME}/ — run: make vault-setup ENV=${ENV_NAME}"
            fi
        else
            warn "Vault at ${VAULT_ADDR} is not reachable or sealed"
        fi
    else
        info "Vault CLI not installed — skipping connectivity check"
    fi
else
    info "VAULT_ADDR not set — skipping Vault check"
fi

echo ""

# -------------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------------
echo -e "${BOLD}── Summary ──${NC}"
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "  ${GREEN}${BOLD}✅ Environment '${ENV_NAME}' is ready for deployment!${NC}"
elif [ $ERRORS -eq 0 ]; then
    echo -e "  ${YELLOW}${BOLD}⚠️  ${WARNINGS} warning(s), but environment is deployable.${NC}"
else
    echo -e "  ${RED}${BOLD}❌ ${ERRORS} error(s), ${WARNINGS} warning(s) — fix before deploying.${NC}"
fi
echo ""

exit $ERRORS
