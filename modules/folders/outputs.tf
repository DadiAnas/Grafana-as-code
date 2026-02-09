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

output "folder_permissions_count" {
  description = "Number of folders with explicit permission overrides"
  value       = length(local.folders_with_permissions)
}

output "folders_with_permissions" {
  description = "List of folder UIDs that have explicit permissions configured"
  value       = local.folders_with_permissions
}
