#!/bin/bash
# Script to bootstrap Vault secrets for Grafana
# Run this once to set up initial secrets structure

set -e

# Check if VAULT_ADDR and VAULT_TOKEN are set
if [ -z "$VAULT_ADDR" ] || [ -z "$VAULT_TOKEN" ]; then
    echo "Error: VAULT_ADDR and VAULT_TOKEN must be set"
    exit 1
fi

ENVIRONMENT=${1:-npr}

echo "Setting up Vault secrets for environment: $ENVIRONMENT"

# Enable KV v2 secrets engine if not already enabled
vault secrets enable -path=grafana kv-v2 2>/dev/null || echo "Secrets engine already enabled"

# Apply policy
echo "Applying Vault policy..."
vault policy write grafana-terraform vault/policies/grafana-terraform.hcl

# Create placeholder secrets (replace with actual values)
echo "Creating placeholder secrets for $ENVIRONMENT..."

# Grafana admin credentials
vault kv put grafana/$ENVIRONMENT/grafana/auth \
    credentials="admin:changeme"

# Datasource credentials (examples)
vault kv put grafana/$ENVIRONMENT/datasources/prometheus-$ENVIRONMENT \
    basicAuthPassword="prometheus-password"

vault kv put grafana/$ENVIRONMENT/datasources/loki-$ENVIRONMENT \
    basicAuthPassword="loki-password"

# Contact point credentials
vault kv put grafana/$ENVIRONMENT/alerting/contact-points/webhook-$ENVIRONMENT \
    authorization_credentials="webhook-token"

# SSO credentials
vault kv put grafana/$ENVIRONMENT/sso/keycloak \
    client_id="grafana-$ENVIRONMENT" \
    client_secret="keycloak-client-secret"

echo "Done! Remember to update placeholder values with actual secrets."
echo ""
echo "To verify secrets:"
echo "  vault kv get grafana/$ENVIRONMENT/grafana/auth"
