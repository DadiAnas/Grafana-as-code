variable "sso_config" {
  description = "SSO configuration from YAML including groups with org_mappings"
  type        = any
}

variable "vault_credentials" {
  description = "SSO credentials from Vault (client_secret)"
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "org_ids" {
  description = "Map of organization names to IDs for org_mapping"
  type        = map(number)
  default     = {}
}
