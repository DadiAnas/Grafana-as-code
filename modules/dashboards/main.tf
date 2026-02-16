# Discover all dashboard JSON files organized by folder
# 
# Directory structure:
#   dashboards/shared/<folder_uid>/<dashboard>.json    → Deployed to ALL environments
#   dashboards/<env>/<folder_uid>/<dashboard>.json     → Deployed to SPECIFIC environment only
#
# Dashboards are created in the organization that owns the target folder.
# Environment-specific dashboards override shared dashboards with the same name.

locals {
  # Find shared dashboard files (deployed to all environments)
  # Pattern: shared/<org>/<folder>/<file>.json
  # We use recursive glob to support nested folders (depth >= 3: shared/org/folder/file)
  shared_dashboard_files = [
    for f in fileset(var.dashboards_path, "shared/**/*.json") : f
    if length(split("/", f)) >= 4
  ]

  # Find environment-specific dashboard files
  # Pattern: <env>/<org>/<folder>/<file>.json
  env_dashboard_files = [
    for f in fileset(var.dashboards_path, "${var.environment}/**/*.json") : f
    if length(split("/", f)) >= 4
  ]

  # Parse shared dashboards
  shared_dashboards = {
    for file in local.shared_dashboard_files :
    replace(replace(file, "shared/", ""), "/", "-") => {
      folder_uid    = dirname(replace(file, "shared/", ""))
      file_path     = "${var.dashboards_path}/${file}"
      dashboard_uid = replace(basename(file), ".json", "")
      source        = "shared"
    }
  }

  # Parse environment-specific dashboards
  env_dashboards = {
    for file in local.env_dashboard_files :
    replace(replace(file, "${var.environment}/", ""), "/", "-") => {
      folder_uid    = dirname(replace(file, "${var.environment}/", ""))
      file_path     = "${var.dashboards_path}/${file}"
      dashboard_uid = replace(basename(file), ".json", "")
      source        = var.environment
    }
  }

  # Merge: environment-specific dashboards override shared ones
  dashboards = {
    for key, dash in merge(local.shared_dashboards, local.env_dashboards) :
    key => dash
    if !contains(var.exclude_folders, dash.folder_uid)
  }
}

resource "grafana_dashboard" "dashboards" {
  for_each = local.dashboards

  config_json = file(each.value.file_path)
  folder      = lookup(var.folder_ids, each.value.folder_uid, null)
  org_id      = lookup(var.folder_org_ids, each.value.folder_uid, null)
  overwrite   = true
  message     = "Updated by Terraform - source: ${each.value.source}"
}
