output "folder_ids" {
  description = "Map of folder UIDs to their IDs"
  value       = { for k, v in grafana_folder.folders : k => v.id }
}

output "folder_uids" {
  description = "Map of folder UIDs to their UIDs (for compatibility)"
  value       = { for k, v in grafana_folder.folders : k => v.uid }
}

output "folder_org_ids" {
  description = "Map of folder UIDs to their organization IDs"
  value       = { for k, v in grafana_folder.folders : k => v.org_id }
}
