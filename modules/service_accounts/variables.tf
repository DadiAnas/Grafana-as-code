variable "service_accounts" {
  description = "Service accounts configuration from YAML"
  type        = any
}

variable "org_ids" {
  description = "Map of organization names to their IDs"
  type        = map(number)
  default     = {}
}
