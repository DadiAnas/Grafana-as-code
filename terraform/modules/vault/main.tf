# Vault Secrets Module
# Retrieves all secrets from HashiCorp Vault for Grafana configuration

# Datasource credentials
data "vault_kv_secret_v2" "datasources" {
  for_each = var.datasource_names

  mount = var.vault_mount
  name  = "${var.environment}/datasources/${each.value}"
}

# Contact point credentials (webhooks, email)
data "vault_kv_secret_v2" "contact_points" {
  for_each = var.contact_point_names

  mount = var.vault_mount
  name  = "${var.environment}/alerting/contact-points/${each.value}"
}

# SSO/Keycloak credentials
data "vault_kv_secret_v2" "sso" {
  count = var.load_sso_secrets ? 1 : 0

  mount = var.vault_mount
  name  = "${var.environment}/sso/keycloak"
}

# Keycloak client secrets (for managing the Keycloak client itself)
data "vault_kv_secret_v2" "keycloak" {
  count = var.load_keycloak_secrets ? 1 : 0

  mount = var.vault_mount
  name  = "${var.environment}/keycloak/client"
}

# Service account tokens (if needed)
data "vault_kv_secret_v2" "service_accounts" {
  for_each = var.service_account_names

  mount = var.vault_mount
  name  = "${var.environment}/service-accounts/${each.value}"
}
