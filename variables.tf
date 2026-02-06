variable "grafana_url" {
  description = "The URL of the Grafana instance"
  type        = string
}

variable "environment" {
  description = "Environment name (npr, preprod, prod)"
  type        = string

  validation {
    condition     = contains(["npr", "preprod", "prod"], var.environment)
    error_message = "Environment must be one of: npr, preprod, prod."
  }
}

# Vault configuration
variable "vault_address" {
  description = "The address of the Vault server"
  type        = string
}

variable "vault_token" {
  description = "Vault token for authentication (use environment variable VAULT_TOKEN in production)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vault_mount" {
  description = "The KV v2 secrets engine mount path in Vault"
  type        = string
  default     = "grafana"
}

# =============================================================================
# KEYCLOAK CONFIGURATION (OPTIONAL)
# These variables are only used when keycloak.enabled = true in config
# Credentials are fetched from Vault at: <env>/keycloak/provider-auth
# =============================================================================

variable "keycloak_url" {
  description = "The URL of the Keycloak server (e.g., http://localhost:8080)"
  type        = string
  default     = ""
}

# Fallback values - these are overridden by Vault secrets if present
variable "keycloak_realm" {
  description = "Default realm for provider auth (can be overridden in Vault secret)"
  type        = string
  default     = "master"
}

variable "keycloak_client_id" {
  description = "Default client ID for provider auth (can be overridden in Vault secret)"
  type        = string
  default     = "admin-cli"
}
