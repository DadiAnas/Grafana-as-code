# =============================================================================
# KEYCLOAK CLIENT MODULE
# Manages Keycloak OAuth client for Grafana SSO integration
# This module is OPTIONAL - set enabled = true to manage Keycloak resources
# =============================================================================

# -----------------------------------------------------------------------------
# KEYCLOAK OPENID CLIENT
# -----------------------------------------------------------------------------
resource "keycloak_openid_client" "grafana" {
  count = var.enabled ? 1 : 0

  realm_id  = var.keycloak_config.realm_id
  client_id = var.keycloak_config.client_id
  name      = var.keycloak_config.client_name
  enabled   = var.keycloak_config.enabled

  description = var.keycloak_config.description
  access_type = var.keycloak_config.access_type

  # OAuth flow settings
  standard_flow_enabled        = var.keycloak_config.standard_flow_enabled
  implicit_flow_enabled        = var.keycloak_config.implicit_flow_enabled
  direct_access_grants_enabled = var.keycloak_config.direct_access_grants_enabled
  service_accounts_enabled     = var.keycloak_config.service_accounts_enabled

  # URLs
  root_url  = var.keycloak_config.root_url
  base_url  = var.keycloak_config.base_url
  admin_url = try(var.keycloak_config.admin_url, null)
  valid_redirect_uris = length(try(var.keycloak_config.valid_redirect_uris, [])) > 0 ? var.keycloak_config.valid_redirect_uris : [
    "${var.keycloak_config.root_url}/login/generic_oauth"
  ]
  valid_post_logout_redirect_uris = length(try(var.keycloak_config.valid_post_logout_redirect_uris, [])) > 0 ? var.keycloak_config.valid_post_logout_redirect_uris : [
    "${var.keycloak_config.root_url}/*"
  ]
  web_origins = var.keycloak_config.web_origins

  # Token settings
  access_token_lifespan = var.keycloak_config.access_token_lifespan

  # Use Vault secret if provided, otherwise let Keycloak generate
  client_secret = try(var.vault_credentials["client_secret"], null)

  login_theme = "keycloak"
}

# -----------------------------------------------------------------------------
# CLIENT ROLES
# Create roles within the Grafana client (Admin, Editor, Viewer)
# -----------------------------------------------------------------------------
resource "keycloak_role" "grafana_roles" {
  for_each = var.enabled ? { for role in var.keycloak_config.roles : role.name => role } : {}

  realm_id    = var.keycloak_config.realm_id
  client_id   = keycloak_openid_client.grafana[0].id
  name        = each.value.name
  description = each.value.description
}

# -----------------------------------------------------------------------------
# GROUPS
# Create groups in Keycloak for organization/team mapping
# The actual role mappings are handled by Grafana SSO org_mapping in sso.yaml
# -----------------------------------------------------------------------------
resource "keycloak_group" "grafana_groups" {
  for_each = var.enabled ? { for group in var.keycloak_config.groups : group.name => group } : {}

  realm_id = var.keycloak_config.realm_id
  name     = each.value.name
}

# -----------------------------------------------------------------------------
# CLIENT SCOPES
# Create custom scopes for Grafana (including 'groups' scope)
# -----------------------------------------------------------------------------
resource "keycloak_openid_client_scope" "grafana_scope" {
  count = var.enabled ? 1 : 0

  realm_id               = var.keycloak_config.realm_id
  name                   = "grafana"
  description            = "Grafana specific claims"
  include_in_token_scope = true
}

# Groups scope - required for group membership in tokens
resource "keycloak_openid_client_scope" "groups_scope" {
  count = var.enabled ? 1 : 0

  realm_id               = var.keycloak_config.realm_id
  name                   = "groups"
  description            = "Group membership scope"
  include_in_token_scope = true
}

# Assign groups scope to the Grafana client as optional scope
resource "keycloak_openid_client_optional_scopes" "grafana_optional_scopes" {
  count = var.enabled ? 1 : 0

  realm_id  = var.keycloak_config.realm_id
  client_id = keycloak_openid_client.grafana[0].id

  optional_scopes = [
    keycloak_openid_client_scope.groups_scope[0].name,
    keycloak_openid_client_scope.grafana_scope[0].name,
  ]
}

# -----------------------------------------------------------------------------
# PROTOCOL MAPPERS
# Map user attributes/roles to OAuth claims
# -----------------------------------------------------------------------------

# Default mappers for Grafana integration
resource "keycloak_openid_user_attribute_protocol_mapper" "email" {
  count = var.enabled ? 1 : 0

  realm_id  = var.keycloak_config.realm_id
  client_id = keycloak_openid_client.grafana[0].id
  name      = "email"

  user_attribute   = "email"
  claim_name       = "email"
  claim_value_type = "String"

  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}

resource "keycloak_openid_user_attribute_protocol_mapper" "username" {
  count = var.enabled ? 1 : 0

  realm_id  = var.keycloak_config.realm_id
  client_id = keycloak_openid_client.grafana[0].id
  name      = "username"

  user_attribute   = "username"
  claim_name       = "preferred_username"
  claim_value_type = "String"

  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}

resource "keycloak_openid_user_attribute_protocol_mapper" "name" {
  count = var.enabled ? 1 : 0

  realm_id  = var.keycloak_config.realm_id
  client_id = keycloak_openid_client.grafana[0].id
  name      = "name"

  user_attribute   = "name"
  claim_name       = "name"
  claim_value_type = "String"

  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}

# Groups mapper for org/team mapping
resource "keycloak_openid_group_membership_protocol_mapper" "groups" {
  count = var.enabled ? 1 : 0

  realm_id  = var.keycloak_config.realm_id
  client_id = keycloak_openid_client.grafana[0].id
  name      = "groups"

  claim_name = "groups"
  full_path  = false  # Use simple group names like "grafana-admins", not "/grafana-admins"

  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}

# Client roles mapper for role-based access
resource "keycloak_openid_user_client_role_protocol_mapper" "roles" {
  count = var.enabled ? 1 : 0

  realm_id  = var.keycloak_config.realm_id
  client_id = keycloak_openid_client.grafana[0].id
  name      = "client-roles"

  claim_name                 = "roles"
  client_id_for_role_mappings = keycloak_openid_client.grafana[0].client_id
  multivalued                = true

  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}

# Custom protocol mappers from config
resource "keycloak_generic_protocol_mapper" "custom" {
  for_each = var.enabled ? { for mapper in var.keycloak_config.mappers : mapper.name => mapper } : {}

  realm_id        = var.keycloak_config.realm_id
  client_id       = keycloak_openid_client.grafana[0].id
  name            = each.value.name
  protocol        = each.value.protocol
  protocol_mapper = each.value.protocol_mapper
  config          = each.value.config
}
