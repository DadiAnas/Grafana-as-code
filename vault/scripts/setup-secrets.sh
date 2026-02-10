#!/bin/bash
# =============================================================================
# VAULT SECRETS SETUP — Template
# =============================================================================
# This script creates the required Vault secrets for a Grafana environment.
# Adapt the values below for your actual environment.
#
# Prerequisites:
#   - Vault CLI installed and configured
#   - VAULT_ADDR and VAULT_TOKEN environment variables set
#   - KV v2 secrets engine enabled at the configured mount path
#
# Usage:
#   export VAULT_ADDR="http://localhost:8200"
#   export VAULT_TOKEN="your-root-token"
#   bash vault/scripts/setup-secrets.sh myenv
#
# For Vault Enterprise namespaces:
#   export VAULT_NAMESPACE="admin/grafana"
#   bash vault/scripts/setup-secrets.sh myenv
# =============================================================================

set -euo pipefail

# Environment name from argument or default
ENV="${1:-myenv}"
MOUNT="${2:-grafana}"

# Vault Enterprise namespace support
if [ -n "${VAULT_NAMESPACE:-}" ]; then
    echo "Using Vault namespace: ${VAULT_NAMESPACE}"
    export VAULT_NAMESPACE
fi

echo "=== Setting up Vault secrets for environment: ${ENV} ==="

# -------------------------------------------------------------------------
# 1. Enable KV v2 secrets engine (skip if already enabled)
# -------------------------------------------------------------------------
vault secrets enable -path="${MOUNT}" -version=2 kv 2>/dev/null || true

# -------------------------------------------------------------------------
# 2. Grafana authentication credentials
# -------------------------------------------------------------------------
# The Terraform provider uses this to authenticate with Grafana.
# "credentials" should be a Grafana API key or service account token.
echo "Creating Grafana auth secret..."
vault kv put "${MOUNT}/${ENV}/grafana/auth" \
  credentials="your-grafana-api-key-or-service-account-token"

# -------------------------------------------------------------------------
# 3. Datasource credentials (optional — only for datasources with use_vault: true)
# -------------------------------------------------------------------------
# Each datasource with use_vault: true needs a secret at:
#   <mount>/<env>/datasources/<datasource-name>
#
# echo "Creating datasource secrets..."
# vault kv put "${MOUNT}/${ENV}/datasources/PostgreSQL" \
#   user="grafana_reader" \
#   password="your-db-password"
#
# vault kv put "${MOUNT}/${ENV}/datasources/InfluxDB" \
#   token="your-influxdb-token"

# -------------------------------------------------------------------------
# 4. SSO / OAuth credentials (optional — only if sso.enabled: true)
# -------------------------------------------------------------------------
# echo "Creating SSO secrets..."
# vault kv put "${MOUNT}/${ENV}/sso/keycloak" \
#   client_secret="your-oauth-client-secret"

# -------------------------------------------------------------------------
# 5. Keycloak provider credentials (optional — only if keycloak.enabled: true)
# -------------------------------------------------------------------------
# echo "Creating Keycloak provider auth secret..."
# vault kv put "${MOUNT}/${ENV}/keycloak/provider-auth" \
#   username="admin" \
#   password="admin-password" \
#   realm="master" \
#   client_id="admin-cli"

# -------------------------------------------------------------------------
# 6. Contact point credentials (optional — for webhook/API tokens)
# -------------------------------------------------------------------------
# echo "Creating contact point secrets..."
# vault kv put "${MOUNT}/${ENV}/contact-points/webhook-alerts" \
#   token="your-webhook-bearer-token"

echo ""
echo "=== Vault secrets for ${ENV} created successfully ==="
echo ""
echo "Verify with: vault kv list ${MOUNT}/${ENV}/"
