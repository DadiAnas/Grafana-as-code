#!/bin/bash
# Rotate a specific secret in Vault
# Usage: ./rotate-secret.sh <environment> <secret-type> <secret-name>
#
# Examples:
#   ./rotate-secret.sh npr datasource PostgreSQL
#   ./rotate-secret.sh prod contact-point webhook-critical
#   ./rotate-secret.sh preprod grafana auth

set -e

ENV=${1:-}
SECRET_TYPE=${2:-}
SECRET_NAME=${3:-}
MOUNT="grafana"

usage() {
    echo "Usage: $0 <environment> <secret-type> <secret-name>"
    echo ""
    echo "Arguments:"
    echo "  environment   npr, preprod, or prod"
    echo "  secret-type   grafana, datasource, contact-point, or sso"
    echo "  secret-name   Name of the secret to rotate"
    echo ""
    echo "Examples:"
    echo "  $0 npr datasource PostgreSQL"
    echo "  $0 prod contact-point webhook-critical"
    echo "  $0 preprod grafana auth"
    echo "  $0 prod sso keycloak"
    exit 1
}

# Validate arguments
if [ -z "$ENV" ] || [ -z "$SECRET_TYPE" ] || [ -z "$SECRET_NAME" ]; then
    usage
fi

if [[ ! "$ENV" =~ ^(npr|preprod|prod)$ ]]; then
    echo "Error: Invalid environment '$ENV'. Must be npr, preprod, or prod."
    exit 1
fi

# Check if VAULT_ADDR and VAULT_TOKEN are set
if [ -z "$VAULT_ADDR" ] || [ -z "$VAULT_TOKEN" ]; then
    echo "Error: VAULT_ADDR and VAULT_TOKEN environment variables must be set"
    exit 1
fi

# Determine the secret path
case $SECRET_TYPE in
    grafana)
        SECRET_PATH="$ENV/grafana/$SECRET_NAME"
        ;;
    datasource)
        SECRET_PATH="$ENV/datasources/$SECRET_NAME"
        ;;
    contact-point)
        SECRET_PATH="$ENV/alerting/contact-points/$SECRET_NAME"
        ;;
    sso)
        SECRET_PATH="$ENV/sso/$SECRET_NAME"
        ;;
    *)
        echo "Error: Invalid secret-type '$SECRET_TYPE'"
        echo "Must be: grafana, datasource, contact-point, or sso"
        exit 1
        ;;
esac

echo "=============================================="
echo "Rotating secret: $MOUNT/$SECRET_PATH"
echo "=============================================="

# Check if secret exists
if ! vault kv get -format=json "$MOUNT/$SECRET_PATH" > /dev/null 2>&1; then
    echo "Error: Secret does not exist at $MOUNT/$SECRET_PATH"
    exit 1
fi

# Get current secret keys
echo ""
echo "Current secret keys:"
vault kv get -format=json "$MOUNT/$SECRET_PATH" | jq -r '.data.data | keys[]' | while read key; do
    echo "  - $key"
done

echo ""
echo "Enter new values for each key (leave empty to keep current value):"
echo ""

# Build the new secret
VAULT_ARGS=""
for key in $(vault kv get -format=json "$MOUNT/$SECRET_PATH" | jq -r '.data.data | keys[]'); do
    current_value=$(vault kv get -format=json "$MOUNT/$SECRET_PATH" | jq -r ".data.data.$key")
    
    read -sp "New value for '$key' (hidden, press Enter to keep current): " new_value
    echo ""
    
    if [ -n "$new_value" ]; then
        VAULT_ARGS="$VAULT_ARGS $key=$new_value"
    else
        VAULT_ARGS="$VAULT_ARGS $key=$current_value"
    fi
done

# Update the secret
echo ""
echo "Updating secret..."
eval vault kv put "$MOUNT/$SECRET_PATH" $VAULT_ARGS

echo ""
echo "=============================================="
echo " Secret rotated successfully!"
echo "=============================================="
echo ""
echo "Next steps:"
echo "  1. Re-run Terraform to apply the new credentials:"
echo "     terraform apply -var-file environments/$ENV.tfvars"
echo "  2. Verify the changes in Grafana"
echo "  3. Update any external systems using the old credentials"
