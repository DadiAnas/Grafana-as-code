# Vault Secrets Module
# Retrieves all secrets from HashiCorp Vault for Grafana configuration
#
# Path layout (paths are relative to var.vault_mount):
#
#   var.vault_path_datasources/<name>        → per-datasource credentials
#   var.vault_path_contact_points/<name>     → per-contact-point secrets
#   var.vault_path_sso                       → SSO / Keycloak OIDC creds
#   var.vault_path_keycloak                  → Keycloak provider-auth
#   var.vault_path_service_accounts/<name>   → per-service-account tokens
#
# All paths default to the layout written by import_from_grafana.py
# but can be overridden via terraform.tfvars — see root variables.tf.

# Datasource credentials
data "vault_kv_secret_v2" "datasources" {
  for_each = var.datasource_names

  mount     = var.vault_mount
  name      = "${replace(var.vault_path_datasources, "{env}", var.environment)}/${each.value}"
  namespace = var.vault_namespace != "" ? var.vault_namespace : null
}

# Contact point credentials (webhooks, Slack, PagerDuty, etc.)
data "vault_kv_secret_v2" "contact_points" {
  for_each = var.contact_point_names

  mount     = var.vault_mount
  name      = "${replace(var.vault_path_contact_points, "{env}", var.environment)}/${each.value}"
  namespace = var.vault_namespace != "" ? var.vault_namespace : null
}

# SSO / Keycloak OIDC credentials
data "vault_kv_secret_v2" "sso" {
  count = var.load_sso_secrets ? 1 : 0

  mount     = var.vault_mount
  name      = replace(var.vault_path_sso, "{env}", var.environment)
  namespace = var.vault_namespace != "" ? var.vault_namespace : null
}

# Keycloak provider-auth credentials (only when Terraform manages the Keycloak client)
data "vault_kv_secret_v2" "keycloak" {
  count = var.load_keycloak_secrets ? 1 : 0

  mount     = var.vault_mount
  name      = replace(var.vault_path_keycloak, "{env}", var.environment)
  namespace = var.vault_namespace != "" ? var.vault_namespace : null
}

# Service account tokens
data "vault_kv_secret_v2" "service_accounts" {
  for_each = var.service_account_names

  mount     = var.vault_mount
  name      = "${replace(var.vault_path_service_accounts, "{env}", var.environment)}/${each.value}"
  namespace = var.vault_namespace != "" ? var.vault_namespace : null
}
