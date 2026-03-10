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

variable "vault_secret_paths" {
  description = "Set of Vault secret paths to fetch (relative to vault_mount). Automatically discovered from YAML configs by scanning for VAULT_SECRET_REQUIRED sentinels."
  type        = set(string)
  default     = []
}
