variable "folder_permissions" {
  description = "Folder permissions configuration from YAML (optional overrides). Folders are auto-discovered from dashboards directory."
  type        = any
  default     = {}
}

variable "dashboards_path" {
  description = "Path to the dashboards directory for auto-discovery"
  type        = string
}

variable "environment" {
  description = "Current environment (npr, preprod, prod)"
  type        = string
}

variable "org_ids" {
  description = "Map of organization names to their IDs"
  type        = map(number)
  default     = {}
}

variable "team_details" {
  description = "Map of team names to their details (team_id, org_id) for folder permissions"
  type = map(object({
    team_id = number
    org_id  = number
  }))
  default = {}
}

variable "user_ids" {
  description = "Map of user emails to their IDs (for folder permissions)"
  type        = map(number)
  default     = {}
}
