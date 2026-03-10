variable "datasources" {
  description = "Datasources configuration from YAML (with VAULT_SECRET_REQUIRED sentinels already resolved)"
  type        = any
}

variable "org_ids" {
  description = "Map of organization names to their IDs"
  type        = map(number)
  default     = {}
}
