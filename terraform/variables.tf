# =============================================================================
# TERRAFORM VARIABLES
# =============================================================================
# These variables are required for connecting to Grafana and Vault.
# Set values in environments/<env>.tfvars or via CLI flags.
# =============================================================================

variable "grafana_url" {
  description = "The URL of your Grafana instance (e.g., http://localhost:3000)"
  type        = string
}

variable "grafana_auth" {
  description = "Grafana auth credentials when use_vault is false. Format: 'admin:password' or a service-account token."
  type        = string
  sensitive   = true
  default     = ""
}

variable "environment" {
  description = "Environment name — must match a directory under envs/"
  type        = string
  # Add your environment names here. You can add as many as you need.
  validation {
    condition     = length(var.environment) > 0
    error_message = "Environment name must not be empty."
  }
}

# =============================================================================
# VAULT CONFIGURATION
# =============================================================================
# HashiCorp Vault is used to store sensitive credentials (Grafana auth,
# datasource passwords, SSO secrets, etc.) instead of in plaintext.
#
# Set use_vault = true to enable Vault integration.  When false (default),
# Grafana auth is taken from var.grafana_auth and all Vault data-sources
# are skipped — ideal for local development and first-time import.
#
# Secret paths are now defined INLINE in YAML configs using the sentinel:
#   VAULT_SECRET_REQUIRED:<vault-path>:<key>
#
# The system automatically:
#   1. Scans all YAML configs for sentinel values
#   2. Fetches the secret from Vault at <vault_mount>/<vault-path>
#   3. Replaces the sentinel with the actual secret value
#
# Provider-level auth (Grafana + Keycloak) still uses dedicated path variables
# because they are needed before config scanning happens.
# =============================================================================

variable "use_vault" {
  description = "Enable Vault integration for secrets management. When false, Grafana auth is taken from grafana_auth and Vault is not contacted."
  type        = bool
  default     = false
}

variable "vault_address" {
  description = "The address of the Vault server (e.g., http://localhost:8200)"
  type        = string
  default     = ""
}

variable "vault_token" {
  description = "Vault token for authentication — prefer setting via VAULT_TOKEN env var"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vault_mount" {
  description = "KV v2 secrets engine mount path in Vault (the engine name, not the full path)"
  type        = string
  default     = "grafana"
}

variable "vault_namespace" {
  description = "Vault Enterprise namespace (e.g., 'admin/team-grafana'). Leave empty for OSS Vault or root namespace."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Provider-level Vault paths (needed before config scanning)
# These are for Grafana and Keycloak PROVIDER authentication only.
# All other secrets use the VAULT_SECRET_REQUIRED sentinel in YAML configs.
# ---------------------------------------------------------------------------

variable "vault_path_grafana_auth" {
  description = "Vault path (within the mount) for the Grafana admin auth secret."
  type        = string
  default     = "{env}/grafana/auth"
}

variable "vault_path_keycloak" {
  description = "Vault path (within the mount) for Keycloak provider-auth credentials."
  type        = string
  default     = "{env}/keycloak/client"
}

# =============================================================================
# KEYCLOAK CONFIGURATION (OPTIONAL)
# =============================================================================
# Only needed if you enable Keycloak-based SSO management.
# Set keycloak.enabled: true in config/shared/keycloak.yaml to activate.
# Credentials are fetched from Vault at: <env>/keycloak/provider-auth
# =============================================================================

variable "keycloak_url" {
  description = "The URL of the Keycloak server (e.g., https://keycloak.example.com)"
  type        = string
  default     = ""
}

variable "keycloak_realm" {
  description = "Keycloak realm for provider auth (can be overridden by Vault secret)"
  type        = string
  default     = "master"
}

variable "keycloak_client_id" {
  description = "Keycloak client ID for provider auth (can be overridden by Vault secret)"
  type        = string
  default     = "admin-cli"
}

# =============================================================================
# GRAFANA EDITION
# =============================================================================

variable "enable_team_sync" {
  description = "Enable team external group sync — requires Grafana Enterprise or Cloud. Set to true when targeting an Enterprise/Cloud instance."
  type        = bool
  default     = false
}

variable "exclude_dashboard_folders" {
  description = "List of folder paths (org/folder) to exclude from dashboard management. Dashboards in these folders will be ignored by Terraform. Example: [\"Main Org./General\", \"Public/Sandbox\"]"
  type        = list(string)
  default     = []
}
