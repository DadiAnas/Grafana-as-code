# =============================================================================
# GRAFANA FOLDERS MODULE
# =============================================================================
# Creates folders and manages granular permissions per team
# 
# PERMISSION INHERITANCE:
# - By default, teams inherit permissions from their org-level role
# - Folder-specific permissions OVERRIDE the org-level defaults
# - Only explicitly defined permissions are managed
#
# IMPORTANT: Teams are organization-scoped in Grafana
# A team can only be granted permissions on folders within the SAME organization.
# Cross-org team permissions are automatically skipped with a warning.
#
# PERMISSION LEVELS:
# - View: Can view dashboards in the folder
# - Edit: Can edit dashboards in the folder
# - Admin: Full control including managing permissions
# =============================================================================

# -----------------------------------------------------------------------------
# FOLDERS
# -----------------------------------------------------------------------------
resource "grafana_folder" "folders" {
  for_each = { for folder in var.folders.folders : folder.uid => folder }

  title  = each.value.name
  uid    = each.value.uid
  org_id = try(var.org_ids[each.value.org], null)
}

# -----------------------------------------------------------------------------
# FOLDER PERMISSIONS (Granular, per-folder overrides)
# -----------------------------------------------------------------------------
# Only manage permissions for folders that have explicit permission overrides
# Teams in the same organization as the folder will be granted permissions
# Cross-org team permissions are skipped (teams are org-scoped in Grafana)

locals {
  # Create a map of folder uid -> resolved org_id
  folder_org_map = {
    for folder in var.folders.folders : folder.uid => try(var.org_ids[folder.org], 1)
  }

  # Flatten folder permissions into a list of permission entries
  # Only include folders that have explicit 'permissions' defined
  # For teams, validate they exist in the same org as the folder
  folder_permissions = flatten([
    for folder in var.folders.folders : [
      for perm in try(folder.permissions, []) : {
        folder_uid = folder.uid
        folder_org = try(var.org_ids[folder.org], 1)
        team       = try(perm.team, null)
        user       = try(perm.user, null)
        role       = try(perm.role, null)
        permission = perm.permission # View, Edit, or Admin
        # Check if team exists in the same org as the folder
        team_in_same_org = try(perm.team, null) != null ? (
          try(var.team_details[perm.team].org_id, -1) == try(var.org_ids[folder.org], 1)
        ) : true # Non-team permissions are always valid
      }
    ]
    if try(folder.permissions, null) != null
  ])

  # Filter to only include valid permissions (teams in same org, or roles/users)
  valid_folder_permissions = [
    for perm in local.folder_permissions : perm
    if perm.team == null || perm.team_in_same_org
  ]

  # Group permissions by folder for the grafana_folder_permission resource
  folders_with_permissions = distinct([
    for perm in local.valid_folder_permissions : perm.folder_uid
  ])

  # Create a map of folder_uid => list of valid permissions
  folder_permissions_map = {
    for folder_uid in local.folders_with_permissions : folder_uid => [
      for perm in local.valid_folder_permissions : perm if perm.folder_uid == folder_uid
    ]
  }
}

resource "grafana_folder_permission" "permissions" {
  for_each = local.folder_permissions_map

  folder_uid = each.key
  org_id     = grafana_folder.folders[each.key].org_id

  # Dynamic permissions for teams (only teams in the same org)
  dynamic "permissions" {
    for_each = [for p in each.value : p if p.team != null]
    content {
      team_id    = try(var.team_details[permissions.value.team].team_id, null)
      permission = permissions.value.permission
    }
  }

  # Dynamic permissions for users
  dynamic "permissions" {
    for_each = [for p in each.value : p if p.user != null]
    content {
      user_id    = try(var.user_ids[permissions.value.user], null)
      permission = permissions.value.permission
    }
  }

  # Dynamic permissions for roles (Viewer, Editor, Admin)
  dynamic "permissions" {
    for_each = [for p in each.value : p if p.role != null]
    content {
      role       = permissions.value.role
      permission = permissions.value.permission
    }
  }

  depends_on = [grafana_folder.folders]
}
