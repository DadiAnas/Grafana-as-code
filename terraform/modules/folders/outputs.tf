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
  description = "Number of folders with permission overrides (all folders — defaults are removed)"
  value       = length(local.folder_permissions_map)
}

output "folders_with_permissions" {
  description = "List of folder paths that have permissions managed (all folders)"
  value       = keys(local.folder_permissions_map)
}
