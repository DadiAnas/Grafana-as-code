## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_vault"></a> [vault](#requirement\_vault) | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_vault"></a> [vault](#provider\_vault) | ~> 4.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [vault_kv_secret_v2.contact_points](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/data-sources/kv_secret_v2) | data source |
| [vault_kv_secret_v2.datasources](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/data-sources/kv_secret_v2) | data source |
| [vault_kv_secret_v2.service_accounts](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/data-sources/kv_secret_v2) | data source |
| [vault_kv_secret_v2.sso](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/data-sources/kv_secret_v2) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_contact_point_names"></a> [contact\_point\_names](#input\_contact\_point\_names) | Set of contact point names to fetch credentials for | `set(string)` | `[]` | no |
| <a name="input_datasource_names"></a> [datasource\_names](#input\_datasource\_names) | Set of datasource names to fetch credentials for | `set(string)` | `[]` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (npr, preprod, prod) | `string` | n/a | yes |
| <a name="input_load_sso_secrets"></a> [load\_sso\_secrets](#input\_load\_sso\_secrets) | Whether to load SSO/Keycloak secrets | `bool` | `true` | no |
| <a name="input_service_account_names"></a> [service\_account\_names](#input\_service\_account\_names) | Set of service account names to fetch credentials for | `set(string)` | `[]` | no |
| <a name="input_vault_mount"></a> [vault\_mount](#input\_vault\_mount) | The KV v2 secrets engine mount path | `string` | `"grafana"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_contact_point_credentials"></a> [contact\_point\_credentials](#output\_contact\_point\_credentials) | Map of contact point names to their credentials |
| <a name="output_datasource_credentials"></a> [datasource\_credentials](#output\_datasource\_credentials) | Map of datasource names to their credentials |
| <a name="output_service_account_credentials"></a> [service\_account\_credentials](#output\_service\_account\_credentials) | Map of service account names to their credentials |
| <a name="output_sso_credentials"></a> [sso\_credentials](#output\_sso\_credentials) | SSO/Keycloak credentials |
