#!/bin/bash
# Verify that all required Vault secrets exist for an environment
# Usage: ./verify-secrets.sh <environment>

set -e

ENV=${1:-npr}
MOUNT="grafana"
ERRORS=0

# Check if VAULT_ADDR and VAULT_TOKEN are set
if [ -z "$VAULT_ADDR" ] || [ -z "$VAULT_TOKEN" ]; then
    echo "Error: VAULT_ADDR and VAULT_TOKEN environment variables must be set"
    exit 1
fi

echo "=============================================="
echo "Verifying Vault secrets for $ENV environment"
echo "Vault Address: $VAULT_ADDR"
echo "=============================================="
echo ""

check_secret() {
    local path=$1
    local description=$2
    
    if vault kv get -format=json "$MOUNT/$path" > /dev/null 2>&1; then
        echo " $description"
        echo "   Path: $MOUNT/$path"
    else
        echo " $description - MISSING!"
        echo "   Expected path: $MOUNT/$path"
        ERRORS=$((ERRORS + 1))
    fi
}

check_secret_key() {
    local path=$1
    local key=$2
    local description=$3
    
    local value=$(vault kv get -format=json "$MOUNT/$path" 2>/dev/null | jq -r ".data.data.$key // empty")
    
    if [ -n "$value" ]; then
        echo " $description"
        echo "   Path: $MOUNT/$path (key: $key)"
    else
        echo " $description - MISSING or EMPTY!"
        echo "   Expected: $MOUNT/$path with key '$key'"
        ERRORS=$((ERRORS + 1))
    fi
}

echo "--- Grafana Credentials ---"
check_secret_key "$ENV/grafana/auth" "credentials" "Grafana admin credentials"

echo ""
echo "--- Datasource Credentials ---"
check_secret "$ENV/datasources/InfluxDB" "InfluxDB credentials"
check_secret "$ENV/datasources/PostgreSQL" "PostgreSQL credentials"
check_secret "$ENV/datasources/Elasticsearch" "Elasticsearch credentials"

echo ""
echo "--- Alerting Contact Points ---"
if [ "$ENV" = "prod" ]; then
    check_secret "$ENV/alerting/contact-points/webhook-prod" "Webhook Prod"
    check_secret "$ENV/alerting/contact-points/webhook-critical" "Webhook Critical"
else
    check_secret "$ENV/alerting/contact-points/webhook-$ENV" "Webhook $ENV"
fi

echo ""
echo "--- SSO Credentials ---"
check_secret "$ENV/sso/keycloak" "Keycloak client credentials"

echo ""
echo "=============================================="
if [ $ERRORS -eq 0 ]; then
    echo " All secrets verified successfully!"
else
    echo " $ERRORS secret(s) missing or invalid"
    echo ""
    echo "Run the setup script to create missing secrets:"
    echo "  ./vault/scripts/setup-$ENV-secrets.sh"
fi
echo "=============================================="

exit $ERRORS
