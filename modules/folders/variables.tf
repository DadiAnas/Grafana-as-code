variable "folders" {
  description = "Folders configuration from YAML"
  type        = any
}

variable "org_ids" {
  description = "Map of organization names to their IDs"
  type        = map(number)
  default     = {}
}

variable "team_ids" {
  description = "Map of team names to their numeric IDs (legacy, use team_details instead)"
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
