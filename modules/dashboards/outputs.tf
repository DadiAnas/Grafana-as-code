output "dashboard_urls" {
  description = "Map of dashboard identifiers to their URLs"
  value       = { for k, v in grafana_dashboard.dashboards : k => v.url }
}

output "dashboard_uids" {
  description = "Map of dashboard identifiers to their UIDs"
  value       = { for k, v in grafana_dashboard.dashboards : k => v.uid }
}

output "dashboard_ids" {
  description = "Map of dashboard identifiers to their IDs"
  value       = { for k, v in grafana_dashboard.dashboards : k => v.id }
}
