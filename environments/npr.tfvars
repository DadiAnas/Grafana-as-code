# NPR (Non-Production) Environment
grafana_url = "http://localhost:3000"
environment = "npr"

# Vault Configuration
vault_address = "http://localhost:8200"
vault_mount   = "grafana"
# vault_token is set via VAULT_TOKEN environment variable for security

# Keycloak Configuration (optional - only needed if keycloak.enabled = true)
keycloak_url = "https://keycloak.example.com"
