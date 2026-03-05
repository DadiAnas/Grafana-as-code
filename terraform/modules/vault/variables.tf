variable "environment" {
  description = "Environment name (dev, staging, prod, …)"
  type        = string
}

variable "vault_mount" {
  description = "KV v2 secrets engine mount path in Vault (engine name only, no leading slash)"
  type        = string
  default     = "grafana"
}

variable "vault_namespace" {
  description = "Vault Enterprise namespace. Leave empty for OSS Vault or the root namespace."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Secret path prefixes (relative to vault_mount)
# Defaults mirror the layout written by import_from_grafana.py.
# Override in terraform.tfvars to match your Vault topology.
# ---------------------------------------------------------------------------

variable "vault_path_grafana_auth" {
  description = "Path within the mount for the Grafana admin auth secret."
  type        = string
  default     = "grafana/auth"
}

variable "vault_path_datasources" {
  description = "Prefix within the mount for per-datasource secrets. The datasource name is appended."
  type        = string
  default     = "grafana/datasources"
}

variable "vault_path_contact_points" {
  description = "Prefix within the mount for contact-point secrets. The contact point name is appended."
  type        = string
  default     = "grafana/alerting/contact-points"
}

variable "vault_path_sso" {
  description = "Path within the mount for SSO / Keycloak OIDC credentials."
  type        = string
  default     = "grafana/sso/keycloak"
}

variable "vault_path_keycloak" {
  description = "Path within the mount for Keycloak provider-auth credentials."
  type        = string
  default     = "grafana/keycloak/client"
}

variable "vault_path_service_accounts" {
  description = "Prefix within the mount for service-account secrets. The account name is appended."
  type        = string
  default     = "grafana/service-accounts"
}

# ---------------------------------------------------------------------------
# Resource names to fetch
# ---------------------------------------------------------------------------

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
  description = "Whether to load SSO/Keycloak secrets from Vault"
  type        = bool
  default     = true
}

variable "load_keycloak_secrets" {
  description = "Whether to load Keycloak provider-auth secrets from Vault (only when Terraform manages the Keycloak client)"
  type        = bool
  default     = false
}
