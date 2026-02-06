# =============================================================================
# ORGANIZATION OUTPUTS
# =============================================================================

output "organization_ids" {
  description = "Map of organization names to their IDs"
  value       = module.organizations.organization_ids
}

output "organization_count" {
  description = "Total number of organizations managed"
  value       = length(module.organizations.organization_ids)
}

# =============================================================================
# FOLDER OUTPUTS
# =============================================================================

output "folder_ids" {
  description = "Map of folder names to their IDs"
  value       = module.folders.folder_ids
}

output "folder_uids" {
  description = "Map of folder names to their UIDs"
  value       = module.folders.folder_uids
}

# =============================================================================
# DATASOURCE OUTPUTS
# =============================================================================

output "datasource_ids" {
  description = "Map of datasource names to their IDs"
  value       = module.datasources.datasource_ids
}

output "datasource_uids" {
  description = "Map of datasource names to their UIDs"
  value       = module.datasources.datasource_uids
}

# =============================================================================
# DASHBOARD OUTPUTS
# =============================================================================

output "dashboard_urls" {
  description = "Map of dashboard names to their URLs"
  value       = module.dashboards.dashboard_urls
}

output "dashboard_uids" {
  description = "Map of dashboard names to their UIDs"
  value       = module.dashboards.dashboard_uids
}

output "dashboard_count" {
  description = "Total number of dashboards deployed"
  value       = length(module.dashboards.dashboard_urls)
}

# =============================================================================
# ALERTING OUTPUTS
# =============================================================================

output "contact_point_names" {
  description = "List of contact point names created"
  value       = module.alerting.contact_point_names
}

output "alert_rule_count" {
  description = "Total number of alert rules deployed"
  value       = module.alerting.alert_rule_count
}

# =============================================================================
# TEAM OUTPUTS
# =============================================================================

output "team_ids" {
  description = "Map of team names to their IDs"
  value       = module.teams.team_ids
}

# =============================================================================
# SERVICE ACCOUNT OUTPUTS
# =============================================================================

output "service_account_ids" {
  description = "Map of service account names to their IDs"
  value       = module.service_accounts.service_account_ids
  sensitive   = true
}

# =============================================================================
# SSO OUTPUTS
# =============================================================================

output "sso_enabled" {
  description = "Whether SSO is enabled for this environment"
  value       = module.sso.sso_enabled
}

output "sso_provider" {
  description = "The SSO provider type (e.g., generic_oauth)"
  value       = module.sso.sso_provider
}

# =============================================================================
# SUMMARY OUTPUT
# =============================================================================

output "deployment_summary" {
  description = "Summary of all resources deployed"
  value = {
    environment      = var.environment
    grafana_url      = var.grafana_url
    organizations    = length(module.organizations.organization_ids)
    folders          = length(module.folders.folder_ids)
    datasources      = length(module.datasources.datasource_ids)
    dashboards       = length(module.dashboards.dashboard_urls)
    teams            = length(module.teams.team_ids)
    service_accounts = length(module.service_accounts.service_account_ids)
    sso_enabled      = module.sso.sso_enabled
  }
}
