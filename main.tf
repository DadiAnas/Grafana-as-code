

terraform {
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 4.25"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
    keycloak = {
      source  = "mrparkers/keycloak"
      version = "~> 4.4"
    }
  }
}

# Vault provider for secrets management
provider "vault" {
  address   = var.vault_address
  token     = var.vault_token != "" ? var.vault_token : null
  namespace = var.vault_namespace != "" ? var.vault_namespace : null
  # Or use other auth methods like approle, kubernetes, etc.
}

# Fetch Grafana credentials from Vault
data "vault_kv_secret_v2" "grafana_auth" {
  mount = var.vault_mount
  name  = "${var.environment}/grafana/auth"
}

# Fetch Keycloak provider credentials from Vault (optional)
# Only fetched when keycloak management is enabled
data "vault_kv_secret_v2" "keycloak_provider_auth" {
  count = local.keycloak_config.enabled ? 1 : 0

  mount = var.vault_mount
  name  = "${var.environment}/keycloak/provider-auth"
}

# Local values for Keycloak provider auth
locals {
  keycloak_auth = local.keycloak_config.enabled ? data.vault_kv_secret_v2.keycloak_provider_auth[0].data : {}
}

provider "grafana" {
  url  = var.grafana_url
  auth = data.vault_kv_secret_v2.grafana_auth.data["credentials"]
}

# Keycloak provider - optional, only used if keycloak module is enabled
# Credentials are fetched from Vault at: <env>/keycloak/provider-auth
# Vault secret should contain:
#   For password grant: { "username": "...", "password": "..." }
#   For client credentials: { "client_secret": "..." }
# Plus optionally: { "realm": "...", "client_id": "..." }
provider "keycloak" {
  url       = var.keycloak_url
  realm     = try(local.keycloak_auth["realm"], var.keycloak_realm)
  client_id = try(local.keycloak_auth["client_id"], var.keycloak_client_id)

  # Password grant (for admin-cli)
  username = try(local.keycloak_auth["username"], null)
  password = try(local.keycloak_auth["password"], null)

  # Client credentials grant (for confidential clients)
  client_secret = try(local.keycloak_auth["client_secret"], null)

  # Skip initial login if Keycloak management is disabled
  initial_login = local.keycloak_config.enabled
}

# Organizations module - must be created first
module "organizations" {
  source = "./modules/organizations"

  organizations = local.organizations_config
}

# Vault secrets module - fetch all secrets from Vault
module "vault_secrets" {
  source = "./modules/vault"

  environment           = var.environment
  vault_mount           = var.vault_mount
  datasource_names      = local.datasource_names
  contact_point_names   = local.contact_point_names
  load_sso_secrets      = true
  load_keycloak_secrets = local.keycloak_config.enabled
}

# Load all modules
# Teams module - must be created early for folder permissions
module "teams" {
  source = "./modules/teams"

  teams            = local.teams_config
  org_ids          = module.organizations.organization_ids
  enable_team_sync = var.enable_team_sync

  depends_on = [module.organizations]
}

module "folders" {
  source = "./modules/folders"

  folder_permissions = local.folders_config
  dashboards_path    = "${abspath(path.module)}/dashboards"
  environment        = var.environment
  org_ids            = module.organizations.organization_ids
  team_details       = module.teams.team_details

  depends_on = [module.organizations, module.teams]
}

module "datasources" {
  source = "./modules/datasources"

  datasources       = local.datasources_config
  org_ids           = module.organizations.organization_ids
  vault_credentials = module.vault_secrets.datasource_credentials

  depends_on = [module.organizations, module.vault_secrets]
}

module "dashboards" {
  source = "./modules/dashboards"

  dashboards_path = "${path.module}/dashboards"
  environment     = var.environment
  folder_ids      = module.folders.folder_ids
  folder_org_ids  = module.folders.folder_org_ids
  exclude_folders = var.exclude_dashboard_folders

  depends_on = [module.folders, module.datasources]
}

module "alerting" {
  source = "./modules/alerting"

  alert_rules           = local.alert_rules_config
  contact_points        = local.contact_points_config
  notification_policies = local.notification_policies_config
  folder_ids            = module.folders.folder_ids
  org_ids               = module.organizations.organization_ids
  vault_credentials     = module.vault_secrets.contact_point_credentials

  depends_on = [module.folders, module.datasources, module.vault_secrets, module.organizations]
}

module "service_accounts" {
  source = "./modules/service_accounts"

  service_accounts = local.service_accounts_config
  org_ids          = module.organizations.organization_ids

  depends_on = [module.organizations]
}

# SSO Configuration - OAuth integration via Grafana API
# Groups and org_mappings are defined in sso.yaml (works with or without Keycloak Terraform management)
module "sso" {
  source = "./modules/sso"

  sso_config        = local.sso_config
  vault_credentials = module.vault_secrets.sso_credentials

  # Pass org IDs to use numeric IDs instead of names (avoids space issues)
  org_ids = module.organizations.organization_ids

  depends_on = [module.vault_secrets, module.organizations]
}

# Keycloak Client Module - OPTIONAL
# Manages the Keycloak OAuth client for Grafana
# Set keycloak.enabled: true in config to activate
module "keycloak" {
  source = "./modules/keycloak"

  enabled           = local.keycloak_config.enabled
  keycloak_config   = local.keycloak_config
  vault_credentials = module.vault_secrets.keycloak_credentials

  depends_on = [module.vault_secrets]
}
