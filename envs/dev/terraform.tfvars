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

# Environment name — used to locate envs/ subdirectory
# Must match: envs/dev/ and envs/dev/dashboards/
environment = "dev"

# ─── Vault Configuration ────────────────────────────────────────────
# HashiCorp Vault for secrets management (datasource passwords, SSO secrets)
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
# # Grafana authentication (alternative to Vault-stored API key)
# # grafana_auth = "admin:admin"          # Only for local dev!
#
# # Terraform state locking timeout
# # lock_timeout = "5m"
#
# # Enable/disable specific resource categories
# # manage_dashboards      = true
# # manage_datasources     = true
# # manage_alerting        = true
# # manage_service_accounts = true
