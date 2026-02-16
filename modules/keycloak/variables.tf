# =============================================================================
# KEYCLOAK MODULE VARIABLES
# =============================================================================

variable "enabled" {
  description = "Whether to create Keycloak resources. Set to false to skip Keycloak management."
  type        = bool
  default     = false
}

variable "keycloak_config" {
  description = "Keycloak client configuration"
  type = object({
    realm_id    = optional(string, "master")
    client_id   = optional(string, "grafana")
    client_name = optional(string, "Grafana")
    description = optional(string, "Grafana OAuth Client")
    enabled     = optional(bool, true)
    access_type = optional(string, "CONFIDENTIAL")

    # OAuth settings
    standard_flow_enabled        = optional(bool, true)
    implicit_flow_enabled        = optional(bool, false)
    direct_access_grants_enabled = optional(bool, false)
    service_accounts_enabled     = optional(bool, false)

    # URLs
    root_url            = optional(string, "http://localhost:3000")
    base_url            = optional(string, "/")
    valid_redirect_uris = optional(list(string), [])
    web_origins         = optional(list(string), ["+"])

    # Token settings
    access_token_lifespan = optional(number, 300)

    # Roles to create
    roles = optional(list(object({
      name        = string
      description = optional(string, "")
    })), [])

    # Groups to create in Keycloak (simple list of names)
    # The actual Grafana role mappings are in sso.yaml, not here
    groups = optional(list(object({
      name = string
    })), [])

    # Protocol mappers
    mappers = optional(list(object({
      name            = string
      protocol        = optional(string, "openid-connect")
      protocol_mapper = string
      config          = map(string)
    })), [])
  })
  default = {
    realm_id  = "master"
    client_id = "grafana"
    root_url  = "http://localhost:3000"
  }
}

variable "vault_credentials" {
  description = "Keycloak client secret from Vault (optional, will be generated if not provided)"
  type        = map(string)
  default     = {}
  sensitive   = true
}
