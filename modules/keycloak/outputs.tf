# =============================================================================
# KEYCLOAK MODULE OUTPUTS
# =============================================================================

output "enabled" {
  description = "Whether Keycloak management is enabled"
  value       = var.enabled
}

output "client_id" {
  description = "The Keycloak client ID"
  value       = var.enabled ? keycloak_openid_client.grafana[0].client_id : null
}

output "client_uuid" {
  description = "The Keycloak internal client UUID"
  value       = var.enabled ? keycloak_openid_client.grafana[0].id : null
}

output "client_secret" {
  description = "The Keycloak client secret (generated or from Vault)"
  value       = var.enabled ? keycloak_openid_client.grafana[0].client_secret : null
  sensitive   = true
}

output "role_ids" {
  description = "Map of role names to their IDs"
  value = var.enabled ? {
    for name, role in keycloak_role.grafana_roles : name => role.id
  } : {}
}

output "group_ids" {
  description = "Map of group names to their IDs"
  value = var.enabled ? {
    for name, group in keycloak_group.grafana_groups : name => group.id
  } : {}
}

output "service_account_user_id" {
  description = "The Keycloak service account user ID (if service accounts enabled)"
  value       = var.enabled && var.keycloak_config.service_accounts_enabled ? keycloak_openid_client.grafana[0].service_account_user_id : null
}
