

terraform {
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 4.27"
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
# When use_vault is false the provider is still declared (required by Terraform)
# but no actual calls are made — all vault data sources use count = 0.
provider "vault" {
  address          = var.use_vault ? var.vault_address : "http://localhost:8200"
  token            = var.use_vault && var.vault_token != "" ? var.vault_token : null
  namespace        = var.use_vault && var.vault_namespace != "" ? var.vault_namespace : null
  skip_child_token = !var.use_vault
}

# Fetch Grafana credentials from Vault (only when use_vault is true)
# Path: var.vault_mount / var.vault_path_grafana_auth
data "vault_kv_secret_v2" "grafana_auth" {
  count = var.use_vault ? 1 : 0

  mount     = var.vault_mount
  name      = replace(var.vault_path_grafana_auth, "{env}", var.environment)
  namespace = var.vault_namespace != "" ? var.vault_namespace : null
}

# Fetch Keycloak provider credentials from Vault (optional)
# Only fetched when keycloak management is enabled AND Vault is active
# Path: var.vault_mount / var.vault_path_keycloak
data "vault_kv_secret_v2" "keycloak_provider_auth" {
  count = var.use_vault && local.keycloak_config.enabled ? 1 : 0

  mount     = var.vault_mount
  name      = replace(var.vault_path_keycloak, "{env}", var.environment)
  namespace = var.vault_namespace != "" ? var.vault_namespace : null
}

# Local values for Keycloak provider auth
locals {
  keycloak_auth = var.use_vault && local.keycloak_config.enabled ? data.vault_kv_secret_v2.keycloak_provider_auth[0].data : {}
}

provider "grafana" {
  url  = var.grafana_url
  auth = var.use_vault ? data.vault_kv_secret_v2.grafana_auth[0].data["credentials"] : var.grafana_auth
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

# =============================================================================
# Vault secrets module — Universal secret fetcher
# =============================================================================
# Fetches ALL secrets discovered by scanning YAML configs for the sentinel
# pattern: VAULT_SECRET_REQUIRED:<vault-path>:<key>
#
# The vault_discovered_paths local (in locals.tf) automatically finds all
# unique Vault paths referenced across all config files.
# =============================================================================
module "vault_secrets" {
  source = "./modules/vault"

  count = var.use_vault ? 1 : 0

  vault_mount        = var.vault_mount
  vault_namespace    = var.vault_namespace
  vault_secret_paths = local.vault_discovered_paths
}

# =============================================================================
# Vault secret resolution
# =============================================================================
# When use_vault is true, this resolves all VAULT_SECRET_REQUIRED sentinels
# in config values by looking up the fetched secrets.
#
# The helper local `_vault_secrets` provides a flat map:
#   { "path" => { "key" => "secret_value", ... }, ... }
#
# Each module receives its config with sentinels already resolved.
# =============================================================================
locals {
  # All fetched secrets: { vault_path => { key => value } }
  _vault_secrets = var.use_vault ? module.vault_secrets[0].secrets : {}

  # Helper function: resolve a single string value
  # If the value matches VAULT_SECRET_REQUIRED:<path>:<key>, look it up in _vault_secrets
  # Otherwise return the value as-is.
  # Note: This is used inline via try() in the resolved config sections below.
}

# =============================================================================
# Resolved configurations — sentinels are replaced with actual Vault values
# =============================================================================
# For each resource config, we walk through the data and replace any string
# matching "VAULT_SECRET_REQUIRED:<path>:<key>" with the corresponding
# Vault secret value.
#
# Terraform's HCL doesn't support recursive functions, so we resolve at the
# specific nesting levels where secrets appear in each resource type.
# =============================================================================

locals {
  # ── Datasources: resolve secure_json_data and top-level secret fields ─────
  resolved_datasources_config = {
    datasources = [
      for ds in local.datasources_config.datasources : merge(ds, {
        # Resolve secure_json_data values
        secure_json_data = {
          for k, v in try(ds.secure_json_data, {}) :
          k => (
            var.use_vault && can(regex("^VAULT_SECRET_REQUIRED:", v))
            ? try(
              local._vault_secrets[regex("VAULT_SECRET_REQUIRED:([^:]+):", v)[0]][regex("VAULT_SECRET_REQUIRED:[^:]+:(.+)$", v)[0]],
              v
            )
            : v
          )
        }
        # Resolve http_headers values (some may be sensitive)
        http_headers = {
          for k, v in try(ds.http_headers, {}) :
          k => (
            var.use_vault && can(regex("^VAULT_SECRET_REQUIRED:", v))
            ? try(
              local._vault_secrets[regex("VAULT_SECRET_REQUIRED:([^:]+):", v)[0]][regex("VAULT_SECRET_REQUIRED:[^:]+:(.+)$", v)[0]],
              v
            )
            : v
          )
        }
      })
    ]
  }

  # ── Contact Points: resolve settings values within each receiver ──────────
  resolved_contact_points_config = {
    contactPoints = [
      for cp in try(local.contact_points_config.contactPoints, []) : merge(cp, {
        receivers = [
          for recv in try(cp.receivers, []) : merge(recv, {
            settings = {
              for k, v in try(recv.settings, {}) :
              k => (
                var.use_vault && try(tostring(v), "") != "" && can(regex("^VAULT_SECRET_REQUIRED:", tostring(v)))
                ? try(
                  local._vault_secrets[regex("VAULT_SECRET_REQUIRED:([^:]+):", tostring(v))[0]][regex("VAULT_SECRET_REQUIRED:[^:]+:(.+)$", tostring(v))[0]],
                  v
                )
                : v
              )
            }
          })
        ]
      })
    ]
  }

  # ── SSO: resolve top-level secret fields (e.g. client_secret) ─────────────
  resolved_sso_config = {
    for k, v in local.sso_config :
    k => (
      var.use_vault && try(tostring(v), "") != "" && can(regex("^VAULT_SECRET_REQUIRED:", try(tostring(v), "")))
      ? try(
        local._vault_secrets[regex("VAULT_SECRET_REQUIRED:([^:]+):", tostring(v))[0]][regex("VAULT_SECRET_REQUIRED:[^:]+:(.+)$", tostring(v))[0]],
        v
      )
      : v
    )
  }

  # ── Keycloak: resolve top-level secret fields ─────────────────────────────
  resolved_keycloak_config = {
    for k, v in local.keycloak_config :
    k => (
      var.use_vault && try(tostring(v), "") != "" && can(regex("^VAULT_SECRET_REQUIRED:", try(tostring(v), "")))
      ? try(
        local._vault_secrets[regex("VAULT_SECRET_REQUIRED:([^:]+):", tostring(v))[0]][regex("VAULT_SECRET_REQUIRED:[^:]+:(.+)$", tostring(v))[0]],
        v
      )
      : v
    )
  }
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

  folder_permissions   = local.folders_config
  base_dashboards_path = "${abspath(local.base_path)}/dashboards"
  env_dashboards_path  = "${abspath(local.env_path)}/dashboards"
  environment          = var.environment
  org_ids              = module.organizations.organization_ids
  team_details         = module.teams.team_details
  # user_ids: optional — add a map of email→Grafana user ID here to enable
  # user-based folder permissions (e.g. { "admin@example.com" = 1 })
  # user_ids           = var.folder_user_ids

  depends_on = [module.organizations, module.teams]
}

module "datasources" {
  source = "./modules/datasources"

  datasources = local.resolved_datasources_config
  org_ids     = module.organizations.organization_ids

  depends_on = [module.organizations]
}

module "dashboards" {
  source = "./modules/dashboards"

  base_dashboards_path = "${abspath(local.base_path)}/dashboards"
  env_dashboards_path  = "${abspath(local.env_path)}/dashboards"
  environment          = var.environment
  folder_ids           = module.folders.folder_ids
  folder_org_ids       = module.folders.folder_org_ids
  exclude_folders      = var.exclude_dashboard_folders

  depends_on = [module.folders, module.datasources]
}

module "alerting" {
  source = "./modules/alerting"

  alert_rules           = local.alert_rules_config
  contact_points        = local.resolved_contact_points_config
  notification_policies = local.notification_policies_config
  folder_ids            = module.folders.folder_ids
  org_ids               = module.organizations.organization_ids

  depends_on = [module.folders, module.datasources, module.organizations]
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

  sso_config = local.resolved_sso_config

  # Pass org IDs to use numeric IDs instead of names (avoids space issues)
  org_ids = module.organizations.organization_ids

  depends_on = [module.organizations]
}

# Keycloak Client Module - OPTIONAL
# Manages the Keycloak OAuth client for Grafana
# Set keycloak.enabled: true in config to activate
module "keycloak" {
  source = "./modules/keycloak"

  enabled         = try(local.keycloak_config.enabled, false)
  keycloak_config = local.keycloak_config

  depends_on = [module.organizations]
}
