# =============================================================================
# DEV ENVIRONMENT — Terraform Variables
# =============================================================================
# This file contains all Terraform variables for the 'dev' environment.
#
# Usage:
#   make plan  ENV=dev
#   make apply ENV=dev
#
# Or directly:
#   terraform plan  -var-file=envs/dev/terraform.tfvars
#   terraform apply -var-file=envs/dev/terraform.tfvars
# =============================================================================

# ─── Grafana Connection ──────────────────────────────────────────────────
# The full URL of your Grafana instance (including protocol and port)
grafana_url = "http://localhost:3000"

# Direct Grafana auth — used when use_vault is false.
# Format: "admin:password" or a service-account/API token (glsa_...).
grafana_auth = "admin:admin"

# Environment name — used to locate envs/ subdirectory
# Must match: envs/dev/ and envs/dev/dashboards/
environment = "dev"

# ─── Vault Configuration (OPTIONAL) ──────────────────────────────────
# Set use_vault = true to enable Vault-based secrets management.
# When false (default), grafana_auth above is used directly.
use_vault     = false
vault_address = "http://localhost:8200"
vault_mount   = "grafana"

# Vault Enterprise namespace (leave commented for OSS Vault or root namespace)
# See: https://developer.hashicorp.com/vault/docs/enterprise/namespaces
# vault_namespace = "admin/grafana"   # e.g., admin/team-x

# The vault token should be set via environment variable for security:
#   export VAULT_TOKEN="your-vault-token"
#
# To set up secrets in Vault:
#   make vault-setup ENV=dev

# ─── Keycloak (Optional) ────────────────────────────────────────────
# Only needed if you enable SSO via Keycloak (see envs/dev/sso.yaml)
# keycloak_url = "https://keycloak.example.com"

# ─── Additional Variables ────────────────────────────────────────────
# Uncomment and set any additional variables your Terraform config needs:
#
# # Terraform state locking timeout
# # lock_timeout = "5m"
#
# # Enable/disable specific resource categories
# # manage_dashboards      = true
# # manage_datasources     = true
# # manage_alerting        = true
# # manage_service_accounts = true
