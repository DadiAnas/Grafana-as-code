#!/bin/bash
# Setup Vault secrets for PreProd environment
# Replace placeholder values with actual secrets before running

set -e

# Check if VAULT_ADDR and VAULT_TOKEN are set
if [ -z "$VAULT_ADDR" ] || [ -z "$VAULT_TOKEN" ]; then
    echo "Error: VAULT_ADDR and VAULT_TOKEN environment variables must be set"
    echo "Example:"
    echo "  export VAULT_ADDR='https://vault.example.com'"
    echo "  export VAULT_TOKEN='your-vault-token'"
    exit 1
fi

ENV="preprod"
MOUNT="grafana"

echo "=============================================="
echo "Setting up Vault secrets for $ENV environment"
echo "Vault Address: $VAULT_ADDR"
echo "=============================================="

# Enable KV v2 secrets engine if not already enabled
echo "Enabling KV v2 secrets engine at '$MOUNT'..."
vault secrets enable -path=$MOUNT kv-v2 2>/dev/null || echo "Secrets engine already enabled"

# =====================================================
# GRAFANA ADMIN CREDENTIALS
# =====================================================
echo "Creating Grafana admin credentials..."
vault kv put $MOUNT/$ENV/grafana/auth \
    credentials="admin:your-preprod-admin-password"

# =====================================================
# DATASOURCE CREDENTIALS
# =====================================================
echo "Creating datasource credentials..."

# InfluxDB
vault kv put $MOUNT/$ENV/datasources/InfluxDB \
    token="your-influxdb-preprod-token"

# PostgreSQL
vault kv put $MOUNT/$ENV/datasources/PostgreSQL \
    user="grafana_readonly" \
    password="your-postgres-preprod-password"

# Elasticsearch
vault kv put $MOUNT/$ENV/datasources/Elasticsearch \
    basicAuthUser="elastic" \
    basicAuthPassword="your-elasticsearch-preprod-password"

# MySQL
vault kv put $MOUNT/$ENV/datasources/MySQL \
    user="grafana_readonly" \
    password="your-mysql-preprod-password"

# Prometheus
vault kv put $MOUNT/$ENV/datasources/Prometheus \
    basicAuthPassword="your-prometheus-preprod-password"

# Loki
vault kv put $MOUNT/$ENV/datasources/Loki \
    basicAuthPassword="your-loki-preprod-password"

# =====================================================
# ALERTING CONTACT POINT CREDENTIALS
# =====================================================
echo "Creating alerting contact point credentials..."

# Webhook PreProd
vault kv put $MOUNT/$ENV/alerting/contact-points/webhook-preprod \
    authorization_credentials="your-webhook-preprod-bearer-token"

# =====================================================
# SSO/KEYCLOAK CREDENTIALS (for Grafana SSO)
# =====================================================
echo "Creating SSO credentials..."
vault kv put $MOUNT/$ENV/sso/keycloak \
    client_id="grafana-preprod" \
    client_secret="your-keycloak-preprod-client-secret"

# =====================================================
# KEYCLOAK PROVIDER AUTH (for Terraform to manage Keycloak)
# Only needed if keycloak.enabled = true in config
# =====================================================
echo "Creating Keycloak provider auth credentials..."

# Option 1: Password Grant
vault kv put $MOUNT/$ENV/keycloak/provider-auth \
    realm="master" \
    client_id="admin-cli" \
    username="admin" \
    password="your-keycloak-admin-password"

# Option 2: Client Credentials Grant (recommended for CI/CD)
# vault kv put $MOUNT/$ENV/keycloak/provider-auth \
#     realm="master" \
#     client_id="terraform-admin" \
#     client_secret="your-terraform-client-secret"

# Keycloak client secret for Grafana OAuth client
vault kv put $MOUNT/$ENV/keycloak/client \
    client_secret="your-grafana-oauth-client-secret"

# =====================================================
# SMTP CREDENTIALS
# =====================================================
echo "Creating SMTP credentials..."
vault kv put $MOUNT/$ENV/smtp \
    user="grafana-alerts@example.com" \
    password="your-smtp-password"

echo ""
echo "=============================================="
echo "PreProd secrets setup complete!"
echo "=============================================="
echo ""
echo "To verify secrets, run:"
echo "  vault kv get $MOUNT/$ENV/grafana/auth"
echo "  vault kv list $MOUNT/$ENV/datasources"
echo ""
echo "IMPORTANT: Update the placeholder values with actual secrets!"
