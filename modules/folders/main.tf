# =============================================================================
# GRAFANA FOLDERS MODULE - Supports nested subfolders
# =============================================================================
# Hierarchy: dashboards/${env}/${org_name}/${folder_uid}/*.json
#
# Rules:
# 1. Organization is inferred from the parent directory name
# 2. Folder UID is the directory name
# 3. Permissions are managed via folders.yaml
# 4. Folders are split into top-level and subfolders to avoid Terraform cycles
# =============================================================================

locals {
  # ---------------------------------------------------------------------------
  # DISCOVER SHARED FOLDERS
  # ---------------------------------------------------------------------------
  shared_folder_paths = toset([
    for file in fileset(var.dashboards_path, "shared/**/*") :
    dirname(replace(file, "shared/", ""))
    if length(split("/", replace(file, "shared/", ""))) >= 2
  ])

  # ---------------------------------------------------------------------------
  # DISCOVER ENV-SPECIFIC FOLDERS
  # ---------------------------------------------------------------------------
  env_folder_paths = toset([
    for file in fileset(var.dashboards_path, "${var.environment}/**/*") :
    dirname(replace(file, "${var.environment}/", ""))
    if length(split("/", replace(file, "${var.environment}/", ""))) >= 2
  ])

  # Combine unique paths
  raw_paths = setunion(local.shared_folder_paths, local.env_folder_paths)

  # Expand paths to ensure all intermediate folders exist
  # e.g., "Org/A/B" -> ["Org/A", "Org/A/B"]
  all_folder_paths = distinct(flatten([
    for path in local.raw_paths : [
      for i in range(1, length(split("/", path))) :
      join("/", slice(split("/", path), 0, i + 1))
    ]
  ]))

  # Helper to parse path into object
  parse_folder = {
    for path in local.all_folder_paths :
    path => {
      uid      = basename(path)
      path     = path
      segments = split("/", path)
      org      = split("/", path)[0]
    }
  }

  # ---------------------------------------------------------------------------
  # SPLIT FOLDERS: top-level (depth == 2) vs subfolders (depth > 2)
  # ---------------------------------------------------------------------------

  # Top-level folders: "OrgName/folder-uid" (exactly 2 segments)
  top_level_folders = {
    for path, data in local.parse_folder : path => {
      uid = data.uid
      name = try(
        [for f in try(var.folder_permissions.folders, []) : f.name if f.uid == data.uid][0],
        title(replace(data.uid, "-", " "))
      )
      org = data.org
      permissions = try(
        [for f in try(var.folder_permissions.folders, []) : f.permissions if f.uid == data.uid][0],
        null
      )
    }
    if length(data.segments) == 2
  }

  # Subfolders: "OrgName/parent/child" (depth > 2)
  sub_folders = {
    for path, data in local.parse_folder : path => {
      uid = data.uid
      name = try(
        [for f in try(var.folder_permissions.folders, []) : f.name if f.uid == data.uid][0],
        title(replace(data.uid, "-", " "))
      )
      org = data.org
      # Parent path: e.g. "Org/A/B" -> "Org/A"
      parent_path = join("/", slice(data.segments, 0, length(data.segments) - 1))
      # Is the parent a top-level folder? (depth == 2)
      parent_is_top_level = length(data.segments) == 3
      permissions = try(
        [for f in try(var.folder_permissions.folders, []) : f.permissions if f.uid == data.uid][0],
        null
      )
    }
    if length(data.segments) > 2
  }

  # Combined view for outputs and permissions (all folders keyed by path)
  auto_folders_combined = merge(
    { for path, f in local.top_level_folders : path => {
      uid         = f.uid
      name        = f.name
      org         = f.org
      permissions = f.permissions
    } },
    { for path, f in local.sub_folders : path => {
      uid         = f.uid
      name        = f.name
      org         = f.org
      permissions = f.permissions
    } }
  )
}

# -----------------------------------------------------------------------------
# CREATE TOP-LEVEL FOLDERS (no parent)
# -----------------------------------------------------------------------------
resource "grafana_folder" "folders" {
  for_each = local.top_level_folders

  title  = each.value.name
  uid    = each.value.uid
  org_id = try(var.org_ids[each.value.org], null)
}

# -----------------------------------------------------------------------------
# CREATE SUBFOLDERS (reference parent from top-level or other subfolders)
# -----------------------------------------------------------------------------
resource "grafana_folder" "subfolders" {
  for_each = local.sub_folders

  title  = each.value.name
  uid    = each.value.uid
  org_id = try(var.org_ids[each.value.org], null)

  # All current subfolders have top-level parents (depth 3: Org/Parent/Child).
  # Referencing grafana_folder.folders avoids a self-referencing cycle.
  parent_folder_uid = grafana_folder.folders[each.value.parent_path].uid
}

# Merge all created folders into a single map for outputs
locals {
  all_created_folders = merge(grafana_folder.folders, grafana_folder.subfolders)
}

# -----------------------------------------------------------------------------
# FOLDER PERMISSIONS
# -----------------------------------------------------------------------------
locals {
  # Create a map of folder path -> resolved org_id
  folder_org_map = {
    for path, folder in local.auto_folders_combined : path => try(var.org_ids[folder.org], 1)
  }

  # Flatten folder permissions
  folder_permissions = flatten([
    for path, folder in local.auto_folders_combined : [
      for perm in try(folder.permissions, []) : {
        folder_path = path
        folder_uid  = folder.uid
        folder_org  = folder.org
        team        = try(perm.team, null)
        user        = try(perm.user, null)
        role        = try(perm.role, null)
        permission  = perm.permission
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

  # Group permissions by folder path
  folders_with_permissions = distinct([
    for perm in local.valid_folder_permissions : perm.folder_path
  ])

  # Create map for resource iteration
  folder_permissions_map = {
    for folder_path in local.folders_with_permissions :
    folder_path => {
      folder_uid = local.auto_folders_combined[folder_path].uid
      folder_org = local.auto_folders_combined[folder_path].org
      perms = [
        for perm in local.valid_folder_permissions : perm if perm.folder_path == folder_path
      ]
    }
  }
}

resource "grafana_folder_permission" "permissions" {
  for_each = local.folder_permissions_map

  # Use statically-known values to avoid dependency cycle
  folder_uid = each.value.folder_uid
  org_id     = try(var.org_ids[each.value.folder_org], null)

  dynamic "permissions" {
    for_each = [for p in each.value.perms : p if p.team != null]
    content {
      team_id    = try(var.team_details[permissions.value.team].team_id, null)
      permission = permissions.value.permission
    }
  }

  dynamic "permissions" {
    for_each = [for p in each.value.perms : p if p.user != null]
    content {
      user_id    = try(var.user_ids[permissions.value.user], null)
      permission = permissions.value.permission
    }
  }

  dynamic "permissions" {
    for_each = [for p in each.value.perms : p if p.role != null]
    content {
      role       = permissions.value.role
      permission = permissions.value.permission
    }
  }

  depends_on = [grafana_folder.folders, grafana_folder.subfolders]
}
