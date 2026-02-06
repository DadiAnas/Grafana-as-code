output "sso_enabled" {
  description = "Whether SSO is enabled"
  value       = var.sso_config.enabled
}

output "sso_provider" {
  description = "SSO provider name"
  value       = var.sso_config.enabled ? var.sso_config.name : null
}
