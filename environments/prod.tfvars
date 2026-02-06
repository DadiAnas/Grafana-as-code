# Production Environment
grafana_url  = "https://grafana.example.com"
environment  = "prod"

# Vault Configuration
# For local testing, use localhost; in production, use actual Vault URL
vault_address = "http://127.0.0.1:8200"
vault_mount   = "grafana"
# vault_token is set via VAULT_TOKEN environment variable for security
