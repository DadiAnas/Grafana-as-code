#!/bin/bash
# =============================================================================
# DEV ENVIRONMENT BOOTSTRAP
# =============================================================================
# Seeds Vault with test secrets and creates a Grafana service account
# for Terraform to use. Run after `docker compose up -d`.
#
# Usage: bash scripts/dev-bootstrap.sh
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-root}"
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-admin}"
ENV="${1:-dev}"
MOUNT="grafana"

echo -e "${BOLD}${CYAN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║          Bootstrapping Dev Environment"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ─── Wait for services ───────────────────────────────────────────────────
wait_for_service() {
    local name="$1" url="$2" max_attempts="${3:-30}"
    local attempt=0
    echo -ne "  Waiting for ${name}..."
    while ! curl -sf "$url" > /dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [ $attempt -ge $max_attempts ]; then
            echo -e " ${RED}FAILED${NC} (timeout after ${max_attempts}s)"
            return 1
        fi
        sleep 1
        echo -ne "."
    done
    echo -e " ${GREEN}OK${NC}"
}

wait_for_service "Grafana" "${GRAFANA_URL}/api/health"
wait_for_service "Vault"   "${VAULT_ADDR}/v1/sys/health"

# ─── 1. Setup Vault ──────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[1/3]${NC} Setting up Vault secrets..."

export VAULT_ADDR VAULT_TOKEN

# Enable KV v2 engine
vault secrets enable -path="${MOUNT}" -version=2 kv 2>/dev/null || true

# Create a Grafana service account + token first
echo -e "  ${YELLOW}→${NC} Creating Grafana service account..."

# Create service account via Grafana API
SA_RESPONSE=$(curl -sf -X POST "${GRAFANA_URL}/api/serviceaccounts" \
    -H "Content-Type: application/json" \
    -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
    -d '{"name":"terraform-dev","role":"Admin","isDisabled":false}' 2>/dev/null || echo '{}')

SA_ID=$(echo "$SA_RESPONSE" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)

if [ -n "$SA_ID" ] && [ "$SA_ID" != "null" ]; then
    # Create token for the service account
    TOKEN_RESPONSE=$(curl -sf -X POST "${GRAFANA_URL}/api/serviceaccounts/${SA_ID}/tokens" \
        -H "Content-Type: application/json" \
        -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
        -d '{"name":"terraform-dev-token","secondsToLive":0}' 2>/dev/null || echo '{}')

    SA_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"key":"[^"]*"' | cut -d'"' -f4)
else
    echo -e "  ${YELLOW}⚠${NC}  Service account may already exist, using basic auth"
    SA_TOKEN=""
fi

# Determine credential to store
if [ -n "$SA_TOKEN" ]; then
    GRAFANA_CREDENTIAL="$SA_TOKEN"
    echo -e "  ${GREEN}✓${NC} Service account created (ID: ${SA_ID})"
else
    GRAFANA_CREDENTIAL="${GRAFANA_USER}:${GRAFANA_PASS}"
    echo -e "  ${YELLOW}⚠${NC}  Using basic auth: ${GRAFANA_USER}:***"
fi

# Store Grafana auth in Vault
vault kv put "${MOUNT}/${ENV}/grafana/auth" \
    credentials="${GRAFANA_CREDENTIAL}" > /dev/null
echo -e "  ${GREEN}✓${NC} Vault: ${MOUNT}/${ENV}/grafana/auth"

# ─── 2. Store SSO mock secrets ────────────────────────────────────────────
echo ""
echo -e "${BLUE}[2/3]${NC} Setting up mock SSO secrets..."

vault kv put "${MOUNT}/${ENV}/sso/keycloak" \
    client_secret="dev-sso-client-secret" > /dev/null
echo -e "  ${GREEN}✓${NC} Vault: ${MOUNT}/${ENV}/sso/keycloak"

# ─── 3. Create dev environment config ────────────────────────────────────
echo ""
echo -e "${BLUE}[3/3]${NC} Generating dev environment..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -d "$PROJECT_ROOT/config/${ENV}" ]; then
    bash "$SCRIPT_DIR/new-env.sh" "${ENV}" \
        --grafana-url="${GRAFANA_URL}" \
        --vault-addr="${VAULT_ADDR}" \
        --vault-mount="${MOUNT}"
else
    echo -e "  ${YELLOW}⚠${NC}  Environment '${ENV}' already exists, skipping scaffolding"
fi

# ─── Summary ─────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ Dev environment bootstrapped successfully!${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Services:"
echo "    Grafana:   ${GRAFANA_URL}  (admin/admin)"
echo "    Vault:     ${VAULT_ADDR}  (token: root)"
echo ""
echo "  Next steps:"
echo "    export VAULT_TOKEN=root"
echo "    make init  ENV=${ENV}"
echo "    make plan  ENV=${ENV}"
echo "    make apply ENV=${ENV}"
echo ""
