variable "environment" {
  description = "Environment name (npr, preprod, prod)"
  type        = string
}

variable "vault_mount" {
  description = "The KV v2 secrets engine mount path"
  type        = string
  default     = "grafana"
}

variable "datasource_names" {
  description = "Set of datasource names to fetch credentials for"
  type        = set(string)
  default     = []
}

variable "contact_point_names" {
  description = "Set of contact point names to fetch credentials for"
  type        = set(string)
  default     = []
}

variable "service_account_names" {
  description = "Set of service account names to fetch credentials for"
  type        = set(string)
  default     = []
}

variable "load_sso_secrets" {
  description = "Whether to load SSO/Keycloak secrets"
  type        = bool
  default     = true
}

variable "load_keycloak_secrets" {
  description = "Whether to load Keycloak client secrets (for managing Keycloak client)"
  type        = bool
  default     = false
}
