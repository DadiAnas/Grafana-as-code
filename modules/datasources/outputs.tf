output "datasource_ids" {
  description = "Map of datasource UIDs to their IDs"
  value       = { for k, v in grafana_data_source.datasources : k => v.id }
}

output "datasource_uids" {
  description = "Map of datasource names to their UIDs"
  value       = { for k, v in grafana_data_source.datasources : v.name => v.uid }
}
