# =============================================================================
# GRAFANA FOLDERS MODULE
# =============================================================================
# Automatically creates folders based on directory structure in dashboards/
# Permissions are managed via folders.yaml configuration
# 
# FOLDER DISCOVERY:
# - Scans dashboards/shared/ and dashboards/{env}/ for subdirectories
# - Each subdirectory becomes a Grafana folder
# - Folder UID = directory name (lowercase with hyphens)
# - Folder Title = directory name (Title Case)
#
# PERMISSION MANAGEMENT:
# - Permissions are defined in folders.yaml
# - By default, teams inherit org-level permissions
# - Use permissions block to override defaults for specific folders
#
# IMPORTANT: Teams are organization-scoped in Grafana
# A team can only be granted permissions on folders within the SAME organization.
# =============================================================================

# -----------------------------------------------------------------------------
# AUTO-DISCOVER FOLDERS FROM DASHBOARDS DIRECTORY
# -----------------------------------------------------------------------------
locals {
  # Discover shared dashboard folders
  shared_folder_dirs = toset([
    for dir in fileset(var.dashboards_path, "shared/*/") :
    trimsuffix(replace(dir, "shared/", ""), "/")
  ])

  # Discover environment-specific dashboard folders
  env_folder_dirs = toset([
    for dir in fileset(var.dashboards_path, "${var.environment}/*/") :
    trimsuffix(replace(dir, "${var.environment}/", ""), "/")
  ])

  # Combine all discovered folders (env overrides shared)
  discovered_folders = setunion(local.shared_folder_dirs, local.env_folder_dirs)

  # Build folder configs from discovered directories
  # Use YAML config to get org and permissions if defined
  auto_folders = {
    for folder_uid in local.discovered_folders : folder_uid => {
      uid = folder_uid
      name = try(
        # Look up name from YAML config if defined
        [for f in try(var.folder_permissions.folders, []) : f.name if f.uid == folder_uid][0],
        # Default to Title Case of UID
        title(replace(folder_uid, "-", " "))
      )
      org = try(
        # Look up org from YAML config if defined
        [for f in try(var.folder_permissions.folders, []) : f.org if f.uid == folder_uid][0],
        # Default to Main Organization
        "Main Organization"
      )
      permissions = try(
        # Look up permissions from YAML config if defined
        [for f in try(var.folder_permissions.folders, []) : f.permissions if f.uid == folder_uid][0],
        # No explicit permissions = inherit org-level defaults
        null
      )
    }
  }
}

# -----------------------------------------------------------------------------
# CREATE FOLDERS
# -----------------------------------------------------------------------------
resource "grafana_folder" "folders" {
  for_each = local.auto_folders

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
    for uid, folder in local.auto_folders : uid => try(var.org_ids[folder.org], 1)
  }

  # Flatten folder permissions into a list of permission entries
  # Only include folders that have explicit 'permissions' defined
  folder_permissions = flatten([
    for uid, folder in local.auto_folders : [
      for perm in try(folder.permissions, []) : {
        folder_uid = uid
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
    if folder.permissions != null
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
