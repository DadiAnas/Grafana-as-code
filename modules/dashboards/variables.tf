variable "dashboards_path" {
  description = "Path to the dashboards directory"
  type        = string
}

variable "environment" {
  description = "Environment name (npr, preprod, prod)"
  type        = string
}

variable "folder_ids" {
  description = "Map of folder UIDs to their IDs"
  type        = map(string)
}

variable "folder_org_ids" {
  description = "Map of folder UIDs to their organization IDs"
  type        = map(number)
  default     = {}
}
