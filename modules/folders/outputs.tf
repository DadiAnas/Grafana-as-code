output "folder_ids" {
  description = "Map of folder paths to their IDs"
  value       = { for k, v in local.all_created_folders : k => v.id }
}

output "folder_uids" {
  description = "Map of folder paths to their UIDs"
  value       = { for k, v in local.all_created_folders : k => v.uid }
}

output "folder_org_ids" {
  description = "Map of folder paths to their organization IDs"
  value       = { for k, v in local.all_created_folders : k => v.org_id }
}

output "folder_permissions_count" {
  description = "Number of folders with explicit permission overrides"
  value       = length(local.folders_with_permissions)
}

output "folders_with_permissions" {
  description = "List of folder paths that have explicit permissions configured"
  value       = local.folders_with_permissions
}
