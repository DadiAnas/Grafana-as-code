#!/bin/bash
# =============================================================================
# VERIFY VAULT SECRETS — Check required secrets exist for an environment
# =============================================================================
# Usage: ./verify-secrets.sh <environment> [mount]
# =============================================================================

set -e

ENV="${1:-myenv}"
MOUNT="${2:-grafana}"
ERRORS=0

if [ -z "${VAULT_ADDR:-}" ] || [ -z "${VAULT_TOKEN:-}" ]; then
    echo "Error: VAULT_ADDR and VAULT_TOKEN environment variables must be set"
    exit 1
fi

echo "=============================================="
echo "Verifying Vault secrets for: ${ENV}"
echo "Vault Address: ${VAULT_ADDR}"
echo "Mount path:    ${MOUNT}"
echo "=============================================="
echo ""

check_secret() {
    local path=$1
    local description=$2

    if vault kv get -format=json "${MOUNT}/${path}" > /dev/null 2>&1; then
        echo "  ✅ ${description}"
        echo "     Path: ${MOUNT}/${path}"
    else
        echo "  ❌ ${description} — MISSING"
        echo "     Expected: ${MOUNT}/${path}"
        ERRORS=$((ERRORS + 1))
    fi
}

check_secret_key() {
    local path=$1
    local key=$2
    local description=$3

    local value
    value=$(vault kv get -format=json "${MOUNT}/${path}" 2>/dev/null | jq -r ".data.data.${key} // empty")

    if [ -n "$value" ]; then
        echo "  ✅ ${description}"
        echo "     Path: ${MOUNT}/${path} (key: ${key})"
    else
        echo "  ❌ ${description} — MISSING or EMPTY"
        echo "     Expected: ${MOUNT}/${path} with key '${key}'"
        ERRORS=$((ERRORS + 1))
    fi
}

# -------------------------------------------------------------------------
# Required: Grafana auth credentials
# -------------------------------------------------------------------------
echo "--- Grafana Credentials ---"
check_secret_key "${ENV}/grafana/auth" "credentials" "Grafana API key / service account token"

# -------------------------------------------------------------------------
# Optional: Datasource credentials (only if use_vault: true)
# -------------------------------------------------------------------------
echo ""
echo "--- Datasource Credentials (if any use_vault: true) ---"
# Uncomment and adapt for your datasources:
# check_secret "${ENV}/datasources/PostgreSQL" "PostgreSQL credentials"
# check_secret "${ENV}/datasources/InfluxDB" "InfluxDB credentials"
echo "  ℹ️  Uncomment datasource checks in verify-secrets.sh for your setup"

# -------------------------------------------------------------------------
# Optional: SSO credentials (only if sso.enabled: true)
# -------------------------------------------------------------------------
echo ""
echo "--- SSO Credentials (if sso.enabled: true) ---"
# check_secret "${ENV}/sso/keycloak" "Keycloak OAuth client secret"
echo "  ℹ️  Uncomment SSO check if you use SSO"

echo ""
echo "=============================================="
if [ $ERRORS -eq 0 ]; then
    echo "  ✅ All required secrets verified!"
else
    echo "  ❌ ${ERRORS} secret(s) missing"
    echo ""
    echo "  Run: bash vault/scripts/setup-secrets.sh ${ENV}"
fi
echo "=============================================="

exit $ERRORS
