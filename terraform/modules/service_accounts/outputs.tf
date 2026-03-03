output "service_account_ids" {
  description = "Map of org:name composite keys to service account IDs"
  value       = { for k, v in grafana_service_account.service_accounts : k => v.id }
}

output "service_account_tokens" {
  description = "Map of org:sa_name-token_name keys to their keys (sensitive)"
  value       = { for k, v in grafana_service_account_token.tokens : k => v.key }
  sensitive   = true
}
