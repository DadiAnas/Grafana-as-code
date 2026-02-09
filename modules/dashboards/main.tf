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
  shared_dashboard_files = fileset(var.dashboards_path, "shared/*/*/*.json")

  # Find environment-specific dashboard files
  # Pattern: <env>/<org>/<folder>/<file>.json
  env_dashboard_files = fileset(var.dashboards_path, "${var.environment}/*/*/*.json")

  # Parse shared dashboards
  shared_dashboards = {
    for file in local.shared_dashboard_files :
    replace(replace(file, "shared/", ""), "/", "-") => {
      folder_uid    = basename(dirname(file))
      file_path     = "${var.dashboards_path}/${file}"
      dashboard_uid = replace(basename(file), ".json", "")
      source        = "shared"
    }
  }

  # Parse environment-specific dashboards
  env_dashboards = {
    for file in local.env_dashboard_files :
    replace(replace(file, "${var.environment}/", ""), "/", "-") => {
      folder_uid    = basename(dirname(file))
      file_path     = "${var.dashboards_path}/${file}"
      dashboard_uid = replace(basename(file), ".json", "")
      source        = var.environment
    }
  }

  # Merge: environment-specific dashboards override shared ones
  dashboards = merge(local.shared_dashboards, local.env_dashboards)
}

resource "grafana_dashboard" "dashboards" {
  for_each = local.dashboards

  config_json = file(each.value.file_path)
  folder      = lookup(var.folder_ids, each.value.folder_uid, null)
  org_id      = lookup(var.folder_org_ids, each.value.folder_uid, null)
  overwrite   = true
  message     = "Updated by Terraform - source: ${each.value.source}"
}
