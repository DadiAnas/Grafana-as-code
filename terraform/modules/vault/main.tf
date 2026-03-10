# Vault Secrets Module — Universal Secret Fetcher
#
# Fetches all secrets from HashiCorp Vault based on a set of discovered paths.
# Paths are extracted automatically from YAML configs by scanning for the
# sentinel pattern: VAULT_SECRET_REQUIRED:<vault-path>:<key>
#
# This module receives a set of unique Vault paths and fetches each one.
# The root module is responsible for scanning configs and building the path set.

data "vault_kv_secret_v2" "secrets" {
  for_each = var.vault_secret_paths

  mount     = var.vault_mount
  name      = each.value
  namespace = var.vault_namespace != "" ? var.vault_namespace : null
}
