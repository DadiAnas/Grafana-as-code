variable "datasources" {
  description = "Datasources configuration from YAML"
  type        = any
}

variable "org_ids" {
  description = "Map of organization names to their IDs"
  type        = map(number)
  default     = {}
}

variable "vault_credentials" {
  description = "Map of datasource names to their credentials from Vault"
  type        = map(map(string))
  default     = {}
  sensitive   = true
}
