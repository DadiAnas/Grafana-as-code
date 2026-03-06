# =============================================================================
# GRAFANA FOLDERS MODULE - Supports nested subfolders
# =============================================================================
# Folders are discovered from THREE sources (union of all):
#   1. base/dashboards/<org>/<folder>/              (shared dashboards)
#   2. envs/<env>/dashboards/<org>/<folder>/         (env-specific dashboards)
#   3. folders.yaml entries with org + uid           (YAML-declared, e.g. alert-only)
#
# Rules:
# 1. Organization is inferred from the parent directory name (or 'org' field in YAML)
# 2. Folder UID is the directory name (or 'uid' field in YAML)
# 3. Permissions are managed via folders.yaml
# 4. Folders are split into top-level and subfolders to avoid Terraform cycles
# 5. "General" folders (uid = "general") are handled via data sources since
#    Grafana auto-creates them in every org - we reference rather than create them
# =============================================================================

locals {
  # List of folder UIDs that Grafana auto-creates (use data source instead of resource)
  builtin_folder_uids = toset(["general"])
  # ---------------------------------------------------------------------------
  # DISCOVER BASE (SHARED) FOLDERS from dashboard directories
  # ---------------------------------------------------------------------------
  shared_folder_paths = toset([
    for file in fileset(var.base_dashboards_path, "**/*") :
    dirname(file)
    if length(split("/", file)) >= 2
  ])

  # ---------------------------------------------------------------------------
  # DISCOVER ENV-SPECIFIC FOLDERS from dashboard directories
  # ---------------------------------------------------------------------------
  env_folder_paths = toset([
    for file in fileset(var.env_dashboards_path, "**/*") :
    dirname(file)
    if length(split("/", file)) >= 2
  ])

  # ---------------------------------------------------------------------------
  # DISCOVER YAML-DECLARED FOLDERS (from folders.yaml)
  # Ensures folders that have no dashboards (e.g., alert-only folders,
  # empty org folders) are still created by Terraform.
  # ---------------------------------------------------------------------------
  yaml_folder_paths = toset([
    for f in try(var.folder_permissions.folders, []) :
    "${try(f.org, "Main Org.")}/${f.uid}"
    if try(f.uid, "") != ""
  ])

  # Combine ALL sources
  raw_paths = setunion(local.shared_folder_paths, local.env_folder_paths, local.yaml_folder_paths)

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
  # Also separate built-in folders (like "General") that Grafana auto-creates
  # ---------------------------------------------------------------------------

  # Top-level folders: "OrgName/folder-uid" (exactly 2 segments)
  # EXCLUDE built-in folders like "general" - they're handled via data source
  top_level_folders = {
    for path, data in local.parse_folder : path => {
      uid = data.uid
      name = try(
        [for f in try(var.folder_permissions.folders, []) : f.name if f.uid == data.uid && try(f.org, "") == data.org][0],
        try(
          [for f in try(var.folder_permissions.folders, []) : f.name if f.uid == data.uid][0],
          title(replace(data.uid, "-", " "))
        )
      )
      org = data.org
      permissions = try(
        [for f in try(var.folder_permissions.folders, []) : f.permissions if f.uid == data.uid && try(f.org, "") == data.org][0],
        try(
          [for f in try(var.folder_permissions.folders, []) : f.permissions if f.uid == data.uid][0],
          null
        )
      )
    }
    if length(data.segments) == 2 && !contains(local.builtin_folder_uids, lower(data.uid))
  }

  # Built-in folders (like "General") - Grafana auto-creates these, use data source
  builtin_folders = {
    for path, data in local.parse_folder : path => {
      uid = data.uid
      name = try(
        [for f in try(var.folder_permissions.folders, []) : f.name if f.uid == data.uid && try(f.org, "") == data.org][0],
        try(
          [for f in try(var.folder_permissions.folders, []) : f.name if f.uid == data.uid][0],
          title(replace(data.uid, "-", " "))
        )
      )
      org = data.org
      org_id = try(var.org_ids[data.org], null) != null ? var.org_ids[data.org] : try(tonumber(data.orgId), 1)
      permissions = try(
        [for f in try(var.folder_permissions.folders, []) : f.permissions if f.uid == data.uid && try(f.org, "") == data.org][0],
        try(
          [for f in try(var.folder_permissions.folders, []) : f.permissions if f.uid == data.uid][0],
          null
        )
      )
    }
    if length(data.segments) == 2 && contains(local.builtin_folder_uids, lower(data.uid))
  }

  # Subfolders: "OrgName/parent/child" (depth > 2)
  sub_folders = {
    for path, data in local.parse_folder : path => {
      uid = data.uid
      name = try(
        [for f in try(var.folder_permissions.folders, []) : f.name if f.uid == data.uid && try(f.org, "") == data.org][0],
        try(
          [for f in try(var.folder_permissions.folders, []) : f.name if f.uid == data.uid][0],
          title(replace(data.uid, "-", " "))
        )
      )
      org = data.org
      # Parent path: e.g. "Org/A/B" -> "Org/A"
      parent_path = join("/", slice(data.segments, 0, length(data.segments) - 1))
      # Parent UID (last segment of parent path)
      parent_uid = length(data.segments) >= 2 ? data.segments[length(data.segments) - 2] : ""
      # Is the parent a top-level folder? (depth == 2)
      parent_is_top_level = length(data.segments) == 3
      # Is the parent a builtin folder (like "General")?
      parent_is_builtin = length(data.segments) == 3 && contains(local.builtin_folder_uids, lower(data.segments[1]))
      permissions = try(
        [for f in try(var.folder_permissions.folders, []) : f.permissions if f.uid == data.uid && try(f.org, "") == data.org][0],
        try(
          [for f in try(var.folder_permissions.folders, []) : f.permissions if f.uid == data.uid][0],
          null
        )
      )
    }
    if length(data.segments) > 2
  }

  # Combined view for outputs and permissions (all folders keyed by path)
  # Includes: top-level folders, subfolders, AND builtin folders (like "General")
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
    } },
    { for path, f in local.builtin_folders : path => {
      uid         = f.uid
      name        = f.name
      org         = f.org
      permissions = f.permissions
    } }
  )
}

# -----------------------------------------------------------------------------
# CREATE TOP-LEVEL FOLDERS (no parent) - excludes built-in folders
# -----------------------------------------------------------------------------
resource "grafana_folder" "folders" {
  for_each = local.top_level_folders

  title  = each.value.name
  uid    = each.value.uid
  org_id = try(var.org_ids[each.value.org], null) != null ? var.org_ids[each.value.org] : try(tonumber(each.value.orgId), null)
}

# -----------------------------------------------------------------------------
# BUILT-IN FOLDERS (like "General")
# Grafana auto-creates these in every org. We use synthetic references instead
# of data source lookups, which fail when orgs are created in the same apply.
# The UID is already known from path discovery (e.g. "general").
# -----------------------------------------------------------------------------
locals {
  builtin_folder_refs = {
    for path, f in local.builtin_folders : path => {
      id     = 0 # General folder is always id 0 within each org
      uid    = f.uid
      title  = f.name
      org_id = f.org_id
    }
  }
}

# -----------------------------------------------------------------------------
# CREATE SUBFOLDERS (reference parent from top-level or other subfolders)
# -----------------------------------------------------------------------------
resource "grafana_folder" "subfolders" {
  for_each = local.sub_folders

  title  = each.value.name
  uid    = each.value.uid
  org_id = try(var.org_ids[each.value.org], null) != null ? var.org_ids[each.value.org] : try(tonumber(each.value.orgId), null)

  # Reference parent folder - could be a regular folder or a builtin (like "General")
  parent_folder_uid = each.value.parent_is_builtin ? (
    local.builtin_folder_refs[each.value.parent_path].uid
  ) : (
    grafana_folder.folders[each.value.parent_path].uid
  )
}

# Merge all created folders into a single map for outputs
# Includes: resources (folders, subfolders) + data sources (builtin)
locals {
  all_created_folders = merge(
    grafana_folder.folders,
    grafana_folder.subfolders,
    # Include builtin folders (like "General") — synthetic refs, no API lookup needed
    { for k, v in local.builtin_folder_refs : k => v }
  )
}

# -----------------------------------------------------------------------------
# FOLDER PERMISSIONS
# -----------------------------------------------------------------------------
# By default Grafana gives Viewer=View and Editor=Edit to all folders.
# We override permissions for EVERY folder so that access is team-based only.
# Folders with no explicit permissions in folders.yaml get only Admin access.
# -----------------------------------------------------------------------------
locals {
  # Paths for built-in folders — excluded from permission management because
  # Grafana does not support setting permissions on auto-created folders (e.g. General)
  builtin_folder_paths = toset(keys(local.builtin_folders))

  # Create a map of folder path -> resolved org_id (excludes builtin folders)
  folder_org_map = {
    for path, folder in local.auto_folders_combined : path => (
      try(var.org_ids[folder.org], null) != null ? var.org_ids[folder.org] : try(tonumber(folder.orgId), 1)
    )
    if !contains(local.builtin_folder_paths, path)
  }

  # Flatten folder permissions (excludes builtin folders)
  folder_permissions = flatten([
    for path, folder in local.auto_folders_combined : [
      for perm in try(coalesce(folder.permissions, []), []) : {
        folder_path = path
        folder_uid  = folder.uid
        folder_org  = folder.org
        team        = try(perm.team, null)
        user        = try(perm.user, null)
        role        = try(perm.role, null)
        permission  = perm.permission
        # Lookup team using composite key "team_name/folder_org"
        team_in_same_org = try(perm.team, null) != null ? (
          tonumber(try(var.team_details["${perm.team}/${folder.org}"].org_id, -1)) == (
            try(var.org_ids[folder.org], null) != null ? var.org_ids[folder.org] : try(tonumber(folder.orgId), 1)
          )
        ) : true
      }
    ]
    if length(try(coalesce(folder.permissions, []), [])) > 0 && !contains(local.builtin_folder_paths, path)
  ])

  # Filter valid permissions
  valid_folder_permissions = [
    for perm in local.folder_permissions : perm
    if perm.team == null || perm.team_in_same_org
  ]

  # Create permission map for ALL folders (not just ones with explicit perms)
  # This ensures default Viewer/Editor access is removed from every folder.
  # Built-in folders (like "General") are EXCLUDED — Grafana does not support
  # setting permissions on them via the API (returns 500).
  folder_permissions_map = {
    for folder_path, folder in local.auto_folders_combined :
    folder_path => {
      folder_uid = folder.uid
      folder_org = folder.org
      perms = [
        for perm in local.valid_folder_permissions : perm if perm.folder_path == folder_path
      ]
    }
    if !contains(local.builtin_folder_paths, folder_path)
  }
}

resource "grafana_folder_permission" "permissions" {
  for_each = local.folder_permissions_map

  # Use statically-known values to avoid dependency cycle
  folder_uid = each.value.folder_uid
  org_id     = local.folder_org_map[each.key]

  dynamic "permissions" {
    for_each = [for p in each.value.perms : p if p.team != null]
    content {
      team_id    = try(var.team_details["${permissions.value.team}/${each.value.folder_org}"].team_id, null)
      permission = permissions.value.permission
    }
  }

  dynamic "permissions" {
    # Only include user permissions when the user can be resolved to an ID
    for_each = [for p in each.value.perms : p if p.user != null && try(var.user_ids[p.user], null) != null]
    content {
      user_id    = var.user_ids[permissions.value.user]
      permission = permissions.value.permission
    }
  }

  dynamic "permissions" {
    # Guard against null or empty-string roles
    for_each = [for p in each.value.perms : p if try(p.role, null) != null && p.role != ""]
    content {
      role       = permissions.value.role
      permission = permissions.value.permission
    }
  }

  depends_on = [grafana_folder.folders, grafana_folder.subfolders]
}
