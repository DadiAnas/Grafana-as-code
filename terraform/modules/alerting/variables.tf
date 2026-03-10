variable "alert_rules" {
  description = "Alert rules configuration from YAML"
  type        = any
}

variable "contact_points" {
  description = "Contact points configuration from YAML (with VAULT_SECRET_REQUIRED sentinels already resolved)"
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
  type        = map(number)
  default     = {}
}
