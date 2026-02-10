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

variable "environment" {
  description = "Environment name — must match a directory under config/ and dashboards/"
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
# See vault/ directory for setup scripts.
# =============================================================================

variable "vault_address" {
  description = "The address of the Vault server (e.g., http://localhost:8200)"
  type        = string
}

variable "vault_token" {
  description = "Vault token for authentication — prefer setting via VAULT_TOKEN env var"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vault_mount" {
  description = "The KV v2 secrets engine mount path in Vault"
  type        = string
  default     = "grafana"
}

variable "vault_namespace" {
  description = "Vault Enterprise namespace (e.g., 'admin/grafana'). Leave empty for OSS Vault or root namespace."
  type        = string
  default     = ""
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
