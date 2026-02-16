# SSO Settings Module
# Manages Grafana SSO configuration via the grafana_sso_settings resource

locals {
  # Get groups from SSO config (works regardless of Keycloak Terraform management)
  sso_groups = try(var.sso_config.groups, [])
  
  # Identify groups that should receive GrafanaAdmin role
  # GrafanaAdmin must be assigned via role_attribute_path, NOT org_mapping
  grafana_admin_groups = distinct(flatten([
    for group in local.sso_groups : [
      for mapping in group.org_mappings : 
        group.name if mapping.role == "GrafanaAdmin"
    ]
  ]))
  
  # Generate role_attribute_path expression for GrafanaAdmin
  # Format: contains(groups[*], 'group1') && 'GrafanaAdmin' || contains(groups[*], 'group2') && 'GrafanaAdmin' || 'None'
  grafana_admin_expression = length(local.grafana_admin_groups) > 0 ? join(
    " || ",
    concat(
      [for group in local.grafana_admin_groups : "contains(groups[*], '${group}') && 'GrafanaAdmin'"],
      ["'None'"]
    )
  ) : null
  
  # Generate org_mapping from SSO groups config with granular per-org roles
  # Format: group_name:org_id:role (using org IDs to avoid space issues)
  # IMPORTANT: Filter out GrafanaAdmin mappings - they must use role_attribute_path instead
  # Supports org: "*" wildcard — meaning "all organizations"
  dynamic_org_mappings = flatten([
    for group in local.sso_groups : [
      for mapping in group.org_mappings :
        mapping.org == "*" ? "${group.name}:*:${mapping.role}" : "${group.name}:${var.org_ids[mapping.org]}:${mapping.role}"
        if mapping.role != "GrafanaAdmin"
    ]
  ])
  
  # Combine dynamic mappings into a single string
  generated_org_mapping = length(local.dynamic_org_mappings) > 0 ? join("\n", local.dynamic_org_mappings) : null
  
  # Use generated mapping if groups provided, otherwise use static org_mapping from sso_config
  final_org_mapping = local.generated_org_mapping != null ? local.generated_org_mapping : try(var.sso_config.org_mapping, null)
  
  # Use generated role_attribute_path for GrafanaAdmin, or fall back to config
  final_role_attribute_path = local.grafana_admin_expression != null ? local.grafana_admin_expression : try(var.sso_config.role_attribute_path, null)
}

resource "grafana_sso_settings" "generic_oauth" {
  count = var.sso_config.enabled ? 1 : 0

  provider_name = "generic_oauth"

  oauth2_settings {
    name                       = var.sso_config.name
    auth_url                   = var.sso_config.auth_url
    token_url                  = var.sso_config.token_url
    api_url                    = var.sso_config.api_url
    client_id                  = var.sso_config.client_id
    client_secret              = var.vault_credentials.client_secret
    
    enabled                    = var.sso_config.enabled
    allow_sign_up              = try(var.sso_config.allow_sign_up, true)
    auto_login                 = try(var.sso_config.auto_login, false)
    scopes                     = try(var.sso_config.scopes, "openid profile email groups")
    use_pkce                   = try(var.sso_config.use_pkce, true)
    use_refresh_token          = try(var.sso_config.use_refresh_token, true)
    
    # Restrict login to specific groups (comma-separated)
    allowed_groups             = try(var.sso_config.allowed_groups, "")
    groups_attribute_path      = try(var.sso_config.groups_attribute_path, "groups[*]")
    
    # Role mapping - GrafanaAdmin must use role_attribute_path, not org_mapping
    # The generated expression handles GrafanaAdmin assignment based on group membership
    role_attribute_path        = local.final_role_attribute_path
    role_attribute_strict      = try(var.sso_config.role_attribute_strict, false)
    skip_org_role_sync         = try(var.sso_config.skip_org_role_sync, false)
    # Enable allow_assign_grafana_admin when we have GrafanaAdmin groups configured
    allow_assign_grafana_admin = length(local.grafana_admin_groups) > 0 ? true : try(var.sso_config.allow_assign_grafana_admin, false)
    
    # Organization mapping - use dynamic mapping from Keycloak groups or static from sso_config
    org_attribute_path         = "groups[*]"
    org_mapping                = local.final_org_mapping
    
    # Team sync
    teams_url                  = try(var.sso_config.teams_url, null)
    team_ids_attribute_path    = try(var.sso_config.team_ids_attribute_path, null)
    
    # Sign out
    signout_redirect_url       = try(var.sso_config.signout_redirect_url, null)
  }
}
