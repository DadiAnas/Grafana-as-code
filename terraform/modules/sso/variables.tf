variable "sso_config" {
  description = "SSO configuration from YAML (with VAULT_SECRET_REQUIRED sentinels already resolved)"
  type        = any
}

variable "org_ids" {
  description = "Map of organization names to IDs for org_mapping"
  type        = map(number)
  default     = {}
}
