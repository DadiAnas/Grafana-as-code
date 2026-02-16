# =============================================================================
# MY ENVIRONMENT - Terraform Variables
# =============================================================================
# Copy this file and adapt it for each Grafana environment you manage.
#
# Usage:
#   terraform plan  -var-file=environments/myenv.tfvars
#   terraform apply -var-file=environments/myenv.tfvars
# =============================================================================

# The URL of your Grafana instance
grafana_url = "http://localhost:3000"

# Environment name — must match a directory under config/ and dashboards/
environment = "myenv"

# Vault Configuration (HashiCorp Vault for secrets management)
vault_address = "http://localhost:8200"
vault_mount   = "grafana"
# vault_token — set via VAULT_TOKEN env variable for security:
#   export VAULT_TOKEN="your-vault-token"

# OSS Team Sync — sync Keycloak group members → Grafana teams via local-exec
# Keycloak is the source of truth: adds/removes Grafana team members to match
# Requires external_groups in teams.yaml + Keycloak credentials in Vault
enable_team_sync_oss = true

# Keycloak Configuration (optional — only if you enable SSO via Keycloak)
# keycloak_url = "https://keycloak.example.com"
