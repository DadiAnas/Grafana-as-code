## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_grafana"></a> [grafana](#requirement\_grafana) | 4.25.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_grafana"></a> [grafana](#provider\_grafana) | 4.25.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [grafana_data_source.datasources](https://registry.terraform.io/providers/grafana/grafana/4.25.0/docs/resources/data_source) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_datasources"></a> [datasources](#input\_datasources) | Datasources configuration from YAML | `any` | n/a | yes |
| <a name="input_org_ids"></a> [org\_ids](#input\_org\_ids) | Map of organization names to their IDs | `map(number)` | `{}` | no |
| <a name="input_vault_credentials"></a> [vault\_credentials](#input\_vault\_credentials) | Map of datasource names to their credentials from Vault | `map(map(string))` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_datasource_ids"></a> [datasource\_ids](#output\_datasource\_ids) | Map of datasource UIDs to their IDs |
| <a name="output_datasource_uids"></a> [datasource\_uids](#output\_datasource\_uids) | Map of datasource names to their UIDs |
