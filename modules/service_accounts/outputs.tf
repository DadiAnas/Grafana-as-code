output "service_account_ids" {
  description = "Map of service account names to their IDs"
  value       = { for k, v in grafana_service_account.service_accounts : k => v.id }
}

output "service_account_tokens" {
  description = "Map of token names to their keys (sensitive)"
  value       = { for k, v in grafana_service_account_token.tokens : k => v.key }
  sensitive   = true
}
