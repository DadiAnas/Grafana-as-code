#!/bin/bash
# Setup Vault secrets for all environments
# This script runs the individual environment setup scripts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if VAULT_ADDR and VAULT_TOKEN are set
if [ -z "$VAULT_ADDR" ] || [ -z "$VAULT_TOKEN" ]; then
    echo "Error: VAULT_ADDR and VAULT_TOKEN environment variables must be set"
    echo "Example:"
    echo "  export VAULT_ADDR='http://localhost:8200'"
    echo "  export VAULT_TOKEN='your-vault-token'"
    exit 1
fi

echo "=============================================="
echo "Setting up Vault secrets for ALL environments"
echo "Vault Address: $VAULT_ADDR"
echo "=============================================="
echo ""

# Parse arguments
ENVIRONMENTS=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --npr)
            ENVIRONMENTS="$ENVIRONMENTS npr"
            shift
            ;;
        --preprod)
            ENVIRONMENTS="$ENVIRONMENTS preprod"
            shift
            ;;
        --prod)
            ENVIRONMENTS="$ENVIRONMENTS prod"
            shift
            ;;
        --all)
            ENVIRONMENTS="npr preprod prod"
            shift
            ;;
        --help)
            echo "Usage: $0 [--npr] [--preprod] [--prod] [--all]"
            echo ""
            echo "Options:"
            echo "  --npr      Setup NPR environment secrets"
            echo "  --preprod  Setup PreProd environment secrets"
            echo "  --prod     Setup Production environment secrets"
            echo "  --all      Setup all environments"
            echo ""
            echo "If no options are provided, you will be prompted to select environments."
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# If no environments specified, prompt user
if [ -z "$ENVIRONMENTS" ]; then
    echo "Select environments to setup:"
    echo ""
    read -p "Setup NPR? (y/n): " setup_npr
    read -p "Setup PreProd? (y/n): " setup_preprod
    read -p "Setup Prod? (y/n): " setup_prod
    
    [ "$setup_npr" = "y" ] && ENVIRONMENTS="$ENVIRONMENTS npr"
    [ "$setup_preprod" = "y" ] && ENVIRONMENTS="$ENVIRONMENTS preprod"
    [ "$setup_prod" = "y" ] && ENVIRONMENTS="$ENVIRONMENTS prod"
fi

if [ -z "$ENVIRONMENTS" ]; then
    echo "No environments selected. Exiting."
    exit 0
fi

echo ""
echo "Will setup secrets for: $ENVIRONMENTS"
echo ""

# Run setup for each selected environment
for env in $ENVIRONMENTS; do
    echo "----------------------------------------------"
    echo "Setting up $env environment..."
    echo "----------------------------------------------"
    
    case $env in
        npr)
            bash "$SCRIPT_DIR/setup-npr-secrets.sh"
            ;;
        preprod)
            bash "$SCRIPT_DIR/setup-preprod-secrets.sh"
            ;;
        prod)
            bash "$SCRIPT_DIR/setup-prod-secrets.sh"
            ;;
    esac
    
    echo ""
done

echo "=============================================="
echo "All selected environments have been configured!"
echo "=============================================="
echo ""
echo "Next steps:"
echo "  1. Update placeholder values with actual secrets"
echo "  2. Verify secrets: vault kv list grafana/"
echo "  3. Apply Terraform: terraform apply -var-file environments/<env>.tfvars"
