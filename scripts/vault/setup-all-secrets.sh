#!/bin/bash
# =============================================================================
# SETUP VAULT SECRETS — All Environments
# =============================================================================
# Runs the generic setup-secrets.sh for one or more environments.
#
# Usage:
#   ./setup-all-secrets.sh myenv
#   ./setup-all-secrets.sh myenv staging production
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "${VAULT_ADDR:-}" ] || [ -z "${VAULT_TOKEN:-}" ]; then
    echo "Error: VAULT_ADDR and VAULT_TOKEN environment variables must be set"
    echo ""
    echo "  export VAULT_ADDR='http://localhost:8200'"
    echo "  export VAULT_TOKEN='your-vault-token'"
    exit 1
fi

if [ $# -eq 0 ]; then
    echo "Usage: $0 <env1> [env2] [env3] ..."
    echo "Example: $0 myenv staging production"
    exit 1
fi

echo "=============================================="
echo "Setting up Vault secrets"
echo "Vault Address: $VAULT_ADDR"
echo "Environments:  $*"
echo "=============================================="
echo ""

for env in "$@"; do
    echo "----------------------------------------------"
    echo "Setting up: ${env}"
    echo "----------------------------------------------"
    bash "$SCRIPT_DIR/setup-secrets.sh" "$env"
    echo ""
done

echo "=============================================="
echo "All environments configured!"
echo "=============================================="
echo ""
echo "Next steps:"
echo "  1. Edit vault/scripts/setup-secrets.sh with actual secret values"
echo "  2. Verify: vault kv list grafana/<env>/"
echo "  3. Apply:  make plan ENV=<env>"
