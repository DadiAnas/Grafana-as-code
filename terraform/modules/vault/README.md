# Vault Secrets Module

This module fetches secrets from HashiCorp Vault for use by Grafana Terraform resources.

## How It Works — Sentinel Pattern

All secrets are declared **inline** in YAML config files using the sentinel value format:

```
VAULT_SECRET_REQUIRED:<vault-path>:<key>
```

Where:
- `<vault-path>` is the path within the Vault KV mount (e.g., `dev/alerting/contact-points/webhook-npr`)
- `<key>` is the key within that secret (e.g., `authorizationCredentials`)

### Example

```yaml
# contact_points.yaml
- name: "webhook-npr"
  receivers:
  - type: "webhook"
    settings:
      authorization_credentials: "VAULT_SECRET_REQUIRED:dev/alerting/contact-points/webhook-npr:authorizationCredentials"
      tlsClientCert: "VAULT_SECRET_REQUIRED:dev/alerting/contact-points/webhook-npr:tlsClientCert"

# datasources.yaml
- name: "PostgreSQL"
  secure_json_data:
    password: "VAULT_SECRET_REQUIRED:dev/datasources/PostgreSQL:password"
```

## Automatic Discovery

The root module (`locals.tf`) automatically:

1. Serializes all YAML configs to JSON
2. Scans for all `VAULT_SECRET_REQUIRED` sentinel values
3. Extracts unique Vault paths
4. Passes them to this module for fetching

No manual configuration of paths or resource names is needed.

## Setup with `make vault-setup`

The `scripts/vault/setup_secrets.py` script performs the reverse operation:

1. Scans all YAML files for `VAULT_SECRET_REQUIRED` sentinels
2. Groups by Vault path
3. Creates placeholder secrets in Vault

```bash
# Create placeholder secrets for an environment
make vault-setup ENV=dev

# Then update the actual values
vault kv put grafana/dev/alerting/contact-points/webhook-npr \
  authorizationCredentials="real-value" \
  tlsClientCert="real-cert"
```

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `vault_mount` | KV v2 mount path | `grafana` |
| `vault_namespace` | Vault Enterprise namespace | `""` |
| `vault_secret_paths` | Set of paths to fetch (auto-discovered) | `[]` |

## Outputs

| Output | Description |
|--------|-------------|
| `secrets` | Map of `{ vault_path => { key => value } }` |
