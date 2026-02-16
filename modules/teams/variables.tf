variable "teams" {
  description = "Teams configuration from YAML"
  type        = any
}

variable "org_ids" {
  description = "Map of organization names to their IDs"
  type        = map(number)
  default     = {}
}

variable "enable_team_sync" {
  description = "Enable team external group sync (requires Grafana Enterprise or Cloud)"
  type        = bool
  default     = false
}
