# Discover all dashboard JSON files organized by folder
#
# Directory structure:
#   base/dashboards/<Org>/<folder>/<dashboard>.json       → Deployed to ALL environments
#   envs/<env>/dashboards/<Org>/<folder>/<dashboard>.json  → Deployed to SPECIFIC environment only
#
# Dashboards are created in the organization that owns the target folder.
# Environment-specific dashboards override shared dashboards with the same name.

locals {
  # Find base (shared) dashboard files (deployed to all environments)
  # Pattern: <org>/<folder>/<file>.json
  shared_dashboard_files = [
    for f in fileset(var.base_dashboards_path, "**/*.json") : f
    if length(split("/", f)) >= 3
  ]

  # Find environment-specific dashboard files
  # Pattern: <org>/<folder>/<file>.json
  env_dashboard_files = [
    for f in fileset(var.env_dashboards_path, "**/*.json") : f
    if length(split("/", f)) >= 3
  ]

  # Parse base (shared) dashboards
  shared_dashboards = {
    for file in local.shared_dashboard_files :
    replace(file, "/", "-") => {
      folder_uid    = dirname(file)
      file_path     = "${var.base_dashboards_path}/${file}"
      dashboard_uid = replace(basename(file), ".json", "")
      source        = "base"
    }
  }

  # Parse environment-specific dashboards
  env_dashboards = {
    for file in local.env_dashboard_files :
    replace(file, "/", "-") => {
      folder_uid    = dirname(file)
      file_path     = "${var.env_dashboards_path}/${file}"
      dashboard_uid = replace(basename(file), ".json", "")
      source        = var.environment
    }
  }

  # Merge: environment-specific dashboards override base ones
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
