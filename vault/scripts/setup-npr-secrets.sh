#!/bin/bash
# Setup Vault secrets for NPR (Non-Production) environment
# Replace placeholder values with actual secrets before running

set -e

# Check if VAULT_ADDR and VAULT_TOKEN are set
if [ -z "$VAULT_ADDR" ] || [ -z "$VAULT_TOKEN" ]; then
    echo "Error: VAULT_ADDR and VAULT_TOKEN environment variables must be set"
    echo "Example:"
    echo "  export VAULT_ADDR='http://localhost:8200'"
    echo "  export VAULT_TOKEN='your-vault-token'"
    exit 1
fi

ENV="npr"
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
    credentials="admin:admin"

# =====================================================
# DATASOURCE CREDENTIALS
# =====================================================
echo "Creating datasource credentials..."

# InfluxDB
vault kv put $MOUNT/$ENV/datasources/InfluxDB \
    token="your-influxdb-npr-token"

# PostgreSQL
vault kv put $MOUNT/$ENV/datasources/PostgreSQL \
    user="grafana_readonly" \
    password="your-postgres-npr-password"

# Elasticsearch (if using authentication)
vault kv put $MOUNT/$ENV/datasources/Elasticsearch \
    basicAuthUser="elastic" \
    basicAuthPassword="your-elasticsearch-npr-password"

# MySQL (if used)
vault kv put $MOUNT/$ENV/datasources/MySQL \
    user="grafana_readonly" \
    password="your-mysql-npr-password"

# Prometheus (if using basic auth)
vault kv put $MOUNT/$ENV/datasources/Prometheus \
    basicAuthPassword="your-prometheus-npr-password"

# Loki (if using basic auth)
vault kv put $MOUNT/$ENV/datasources/Loki \
    basicAuthPassword="your-loki-npr-password"

# =====================================================
# ALERTING CONTACT POINT CREDENTIALS
# =====================================================
echo "Creating alerting contact point credentials..."

# Webhook NPR
vault kv put $MOUNT/$ENV/alerting/contact-points/webhook-npr \
    authorization_credentials="your-webhook-npr-bearer-token"

# =====================================================
# SSO/KEYCLOAK CREDENTIALS
# =====================================================
# SSO/KEYCLOAK CREDENTIALS (for Grafana SSO)
# =====================================================
echo "Creating SSO credentials..."
vault kv put $MOUNT/$ENV/sso/keycloak \
    client_id="grafana-terraform" \
    client_secret="XepS4h00Rl1RnR51BgcK016uuhEvf4Ep"

# =====================================================
# KEYCLOAK PROVIDER AUTH (for Terraform to manage Keycloak)
# Only needed if keycloak.enabled = true in config
# Choose ONE of the following auth methods:
# =====================================================
echo "Creating Keycloak provider auth credentials..."

# Option 1: Password Grant (simpler, use with admin-cli)
# vault kv put $MOUNT/$ENV/keycloak/provider-auth \
#     realm="master" \
#     client_id="admin-cli" \
#     username="admin" \
#     password="your-keycloak-admin-password"

# Option: Client credentials with grafana-realm
vault kv put $MOUNT/$ENV/keycloak/provider-auth \
    realm="grafana-realm" \
    client_id="grafana" \
    client_secret="XepS4h00Rl1RnR51BgcK016uuhEvf4Ep"

# Option 2: Client Credentials Grant (recommended for CI/CD)
# Uncomment below and comment out Option 1 if using a dedicated service account
# vault kv put $MOUNT/$ENV/keycloak/provider-auth \
#     realm="master" \
#     client_id="terraform-admin" \
#     client_secret="your-terraform-client-secret"

# =====================================================
# KEYCLOAK CLIENT SECRET (for the Grafana OAuth client managed by Terraform)
# Only needed if keycloak.enabled = true in config
# =====================================================
echo "Creating Keycloak client credentials..."
vault kv put $MOUNT/$ENV/keycloak/client \
    client_secret="XepS4h00Rl1RnR51BgcK016uuhEvf4Ep"

# =====================================================
# SMTP CREDENTIALS (if using authenticated SMTP)
# =====================================================
echo "Creating SMTP credentials..."
vault kv put $MOUNT/$ENV/smtp \
    user="grafana-alerts@example.com" \
    password="your-smtp-password"

echo ""
echo "=============================================="
echo "NPR secrets setup complete!"
echo "=============================================="
echo ""
echo "To verify secrets, run:"
echo "  vault kv get $MOUNT/$ENV/grafana/auth"
echo "  vault kv list $MOUNT/$ENV/datasources"
echo ""
echo "IMPORTANT: Update the placeholder values with actual secrets!"
