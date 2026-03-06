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
# Secret layout (all paths are relative to vault_mount):
#
#   <vault_path_grafana_auth>              → Grafana admin credentials
#   <vault_path_datasources>/<ds-name>    → per-datasource credentials
#   <vault_path_contact_points>/<cp-name> → per-contact-point secrets
#   <vault_path_sso>                      → SSO / Keycloak OIDC creds
#   <vault_path_keycloak>                 → Keycloak provider auth
#   <vault_path_service_accounts>/<name>  → per-service-account tokens
#
# All path variables default to the conventional layout used by import_from_grafana.py.
# Override any of them in your environment's terraform.tfvars if your Vault differs.
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
# Vault secret path prefixes
# Each variable is the path suffix appended after vault_mount.
# You can use the literal string {env} which will be replaced by var.environment.
# ---------------------------------------------------------------------------

variable "vault_path_grafana_auth" {
  description = "Vault path (within the mount) for the Grafana admin auth secret."
  type        = string
  default     = "{env}/grafana/auth"
}

variable "vault_path_datasources" {
  description = "Vault path prefix for per-datasource credential secrets. The datasource name is appended."
  type        = string
  default     = "{env}/datasources"
}

variable "vault_path_contact_points" {
  description = "Vault path prefix for alerting contact-point credential secrets. The contact point name is appended."
  type        = string
  default     = "{env}/alerting/contact-points"
}

variable "vault_path_sso" {
  description = "Vault path (within the mount) for SSO / Keycloak OIDC credentials."
  type        = string
  default     = "{env}/sso/keycloak"
}

variable "vault_path_keycloak" {
  description = "Vault path (within the mount) for Keycloak provider-auth credentials."
  type        = string
  default     = "{env}/keycloak/client"
}

variable "vault_path_service_accounts" {
  description = "Vault path prefix for per-service-account credential secrets. The service account name is appended."
  type        = string
  default     = "{env}/service-accounts"
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
