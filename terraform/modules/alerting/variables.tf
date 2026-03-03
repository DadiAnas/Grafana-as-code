variable "alert_rules" {
  description = "Alert rules configuration from YAML"
  type        = any
}

variable "contact_points" {
  description = "Contact points configuration from YAML"
  type        = any
}

variable "notification_policies" {
  description = "Notification policies configuration from YAML"
  type        = any
}

variable "mute_timings" {
  description = "Mute timings configuration from YAML"
  type        = any
  default     = { mute_timings = [] }
}

variable "folder_ids" {
  description = "Map of folder UIDs to their IDs"
  type        = map(string)
}

variable "org_ids" {
  description = "Map of organization names to their IDs"
  type        = map(string)
  default     = {}
}

variable "vault_credentials" {
  description = "Map of contact point names to their credentials from Vault"
  type        = map(map(string))
  default     = {}
  sensitive   = true
}
