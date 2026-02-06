#!/bin/bash
# Setup Vault secrets for Production environment
# Replace placeholder values with actual secrets before running
# 
# WARNING: This script contains production secret placeholders.
# Handle with care and never commit actual secrets to version control.

set -e

# Check if VAULT_ADDR and VAULT_TOKEN are set
if [ -z "$VAULT_ADDR" ] || [ -z "$VAULT_TOKEN" ]; then
    echo "Error: VAULT_ADDR and VAULT_TOKEN environment variables must be set"
    echo "Example:"
    echo "  export VAULT_ADDR='https://vault.example.com'"
    echo "  export VAULT_TOKEN='your-vault-token'"
    exit 1
fi

ENV="prod"
MOUNT="grafana"

echo "=============================================="
echo "Setting up Vault secrets for $ENV environment"
echo "Vault Address: $VAULT_ADDR"
echo "=============================================="
echo ""
echo "⚠️  WARNING: You are setting up PRODUCTION secrets!"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

# Enable KV v2 secrets engine if not already enabled
echo "Enabling KV v2 secrets engine at '$MOUNT'..."
vault secrets enable -path=$MOUNT kv-v2 2>/dev/null || echo "Secrets engine already enabled"

# =====================================================
# GRAFANA ADMIN CREDENTIALS
# =====================================================
echo "Creating Grafana admin credentials..."
vault kv put $MOUNT/$ENV/grafana/auth \
    credentials="admin:your-prod-admin-password"

# =====================================================
# DATASOURCE CREDENTIALS
# =====================================================
echo "Creating datasource credentials..."

# InfluxDB
vault kv put $MOUNT/$ENV/datasources/InfluxDB \
    token="your-influxdb-prod-token"

# PostgreSQL
vault kv put $MOUNT/$ENV/datasources/PostgreSQL \
    user="grafana_readonly" \
    password="your-postgres-prod-password"

# Elasticsearch
vault kv put $MOUNT/$ENV/datasources/Elasticsearch \
    basicAuthUser="elastic" \
    basicAuthPassword="your-elasticsearch-prod-password"

# MySQL
vault kv put $MOUNT/$ENV/datasources/MySQL \
    user="grafana_readonly" \
    password="your-mysql-prod-password"

# Prometheus
vault kv put $MOUNT/$ENV/datasources/Prometheus \
    basicAuthPassword="your-prometheus-prod-password"

# Loki
vault kv put $MOUNT/$ENV/datasources/Loki \
    basicAuthPassword="your-loki-prod-password"

# =====================================================
# ALERTING CONTACT POINT CREDENTIALS
# =====================================================
echo "Creating alerting contact point credentials..."

# Webhook Prod (standard alerts)
vault kv put $MOUNT/$ENV/alerting/contact-points/webhook-prod \
    authorization_credentials="your-webhook-prod-bearer-token"

# Webhook Critical (high-priority alerts)
vault kv put $MOUNT/$ENV/alerting/contact-points/webhook-critical \
    authorization_credentials="your-webhook-critical-bearer-token"

# =====================================================
# SSO/KEYCLOAK CREDENTIALS (for Grafana SSO)
# =====================================================
echo "Creating SSO credentials..."
vault kv put $MOUNT/$ENV/sso/keycloak \
    client_id="grafana-prod" \
    client_secret="your-keycloak-prod-client-secret"

# =====================================================
# KEYCLOAK PROVIDER AUTH (for Terraform to manage Keycloak)
# Only needed if keycloak.enabled = true in config
# PRODUCTION: Use client credentials grant (more secure)
# =====================================================
echo "Creating Keycloak provider auth credentials..."

# Client Credentials Grant (recommended for production)
vault kv put $MOUNT/$ENV/keycloak/provider-auth \
    realm="master" \
    client_id="terraform-admin" \
    client_secret="your-terraform-prod-client-secret"

# Keycloak client secret for Grafana OAuth client
vault kv put $MOUNT/$ENV/keycloak/client \
    client_secret="your-grafana-oauth-prod-client-secret"

# =====================================================
# SMTP CREDENTIALS
# =====================================================
echo "Creating SMTP credentials..."
vault kv put $MOUNT/$ENV/smtp \
    user="grafana-alerts@example.com" \
    password="your-smtp-password"

echo ""
echo "=============================================="
echo "Production secrets setup complete!"
echo "=============================================="
echo ""
echo "To verify secrets, run:"
echo "  vault kv get $MOUNT/$ENV/grafana/auth"
echo "  vault kv list $MOUNT/$ENV/datasources"
echo ""
echo "IMPORTANT: Update the placeholder values with actual secrets!"
echo ""
echo "Security Reminders:"
echo "  - Rotate secrets regularly"
echo "  - Use strong, unique passwords"
echo "  - Enable audit logging in Vault"
echo "  - Restrict access to production secrets"
