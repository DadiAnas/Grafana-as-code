output "secrets" {
  description = "Map of vault paths to their secret data. Keys are the vault paths, values are maps of key=>value."
  value = {
    for path, secret in data.vault_kv_secret_v2.secrets : path => secret.data
  }
  sensitive = true
}
