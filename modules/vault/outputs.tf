output "datasource_credentials" {
  description = "Map of datasource names to their credentials"
  value = {
    for name, secret in data.vault_kv_secret_v2.datasources : name => secret.data
  }
  sensitive = true
}

output "contact_point_credentials" {
  description = "Map of contact point names to their credentials"
  value = {
    for name, secret in data.vault_kv_secret_v2.contact_points : name => secret.data
  }
  sensitive = true
}

output "sso_credentials" {
  description = "SSO/Keycloak credentials"
  value       = var.load_sso_secrets ? data.vault_kv_secret_v2.sso[0].data : {}
  sensitive   = true
}

output "keycloak_credentials" {
  description = "Keycloak client credentials (for managing Keycloak client)"
  value       = var.load_keycloak_secrets ? data.vault_kv_secret_v2.keycloak[0].data : {}
  sensitive   = true
}

output "service_account_credentials" {
  description = "Map of service account names to their credentials"
  value = {
    for name, secret in data.vault_kv_secret_v2.service_accounts : name => secret.data
  }
  sensitive = true
}
