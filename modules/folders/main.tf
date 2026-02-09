# =============================================================================
# GRAFANA FOLDERS MODULE - Updated for new directory structure
# =============================================================================
# Hierarchy: dashboards/${env}/${org_name}/${folder_uid}/*.json
#
# Rules:
# 1. Organization is inferred from the parent directory name
# 2. Folder UID is the directory name
# 3. Permissions are managed via folders.yaml
# =============================================================================

locals {
  # ---------------------------------------------------------------------------
  # DISCOVER SHARED FOLDERS
  # ---------------------------------------------------------------------------
  # Pattern: shared/<org_name>/<folder_uid>
  # Returns list of relative paths: "Main Organization/infrastructure"
  shared_folder_paths = toset([
    for file in fileset(var.dashboards_path, "shared/**/*") :
    dirname(replace(file, "shared/", ""))
    if length(split("/", replace(file, "shared/", ""))) == 2 # Only depth 2 (org/folder)
  ])

  # ---------------------------------------------------------------------------
  # DISCOVER ENV-SPECIFIC FOLDERS
  # ---------------------------------------------------------------------------
  # Pattern: ${env}/<org_name>/<folder_uid>
  env_folder_paths = toset([
    for file in fileset(var.dashboards_path, "${var.environment}/**/*") :
    dirname(replace(file, "${var.environment}/", ""))
    if length(split("/", replace(file, "${var.environment}/", ""))) == 2
  ])

  # Combine unique Folder UIDs across shared and env
  # We identify folders by UID, but we need to track Org association too.
  # If a folder UID exists in both environments under DIFFERENT orgs, that's a conflict.
  # We assume Folder UID is unique globally, so we key by UID.

  # Helper to parse path into object
  # path format: "Org Name/folder-uid"
  parse_folder = {
    for path in setunion(local.shared_folder_paths, local.env_folder_paths) :
    basename(path) => { # Key by folder_uid
      uid = basename(path)
      org = dirname(path)
    }
  }

  # Build final folder config
  auto_folders = {
    for uid, data in local.parse_folder : uid => {
      uid = uid
      name = try(
        # Look up name from YAML config if defined
        [for f in try(var.folder_permissions.folders, []) : f.name if f.uid == uid][0],
        # Default to Title Case of UID
        title(replace(uid, "-", " "))
      )
      # Org is strictly inferred from directory structure
      org = data.org

      permissions = try(
        # Look up permissions from YAML config if defined
        [for f in try(var.folder_permissions.folders, []) : f.permissions if f.uid == uid][0],
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
# FOLDER PERMISSIONS
# -----------------------------------------------------------------------------
locals {
  # Create a map of folder uid -> resolved org_id
  folder_org_map = {
    for uid, folder in local.auto_folders : uid => try(var.org_ids[folder.org], 1)
  }

  # Flatten folder permissions
  folder_permissions = flatten([
    for uid, folder in local.auto_folders : [
      for perm in try(folder.permissions, []) : {
        folder_uid = uid
        folder_org = try(var.org_ids[folder.org], 1)
        team       = try(perm.team, null)
        user       = try(perm.user, null)
        role       = try(perm.role, null)
        permission = perm.permission
        # Validate team is in same org
        team_in_same_org = try(perm.team, null) != null ? (
          try(var.team_details[perm.team].org_id, -1) == try(var.org_ids[folder.org], 1)
        ) : true
      }
    ]
    if folder.permissions != null
  ])

  # Filter valid permissions
  valid_folder_permissions = [
    for perm in local.folder_permissions : perm
    if perm.team == null || perm.team_in_same_org
  ]

  # Group permissions by folder
  folders_with_permissions = distinct([
    for perm in local.valid_folder_permissions : perm.folder_uid
  ])

  # Create map for resource iteration
  folder_permissions_map = {
    for folder_uid in local.folders_with_permissions :
    folder_uid => [
      for perm in local.valid_folder_permissions : perm if perm.folder_uid == folder_uid
    ]
  }
}

resource "grafana_folder_permission" "permissions" {
  for_each = local.folder_permissions_map

  folder_uid = each.key
  org_id     = grafana_folder.folders[each.key].org_id

  dynamic "permissions" {
    for_each = [for p in each.value : p if p.team != null]
    content {
      team_id    = try(var.team_details[permissions.value.team].team_id, null)
      permission = permissions.value.permission
    }
  }

  dynamic "permissions" {
    for_each = [for p in each.value : p if p.user != null]
    content {
      user_id    = try(var.user_ids[permissions.value.user], null)
      permission = permissions.value.permission
    }
  }

  dynamic "permissions" {
    for_each = [for p in each.value : p if p.role != null]
    content {
      role       = permissions.value.role
      permission = permissions.value.permission
    }
  }

  depends_on = [grafana_folder.folders]
}
