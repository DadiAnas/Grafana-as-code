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
| [grafana_service_account.service_accounts](https://registry.terraform.io/providers/grafana/grafana/4.25.0/docs/resources/service_account) | resource |
| [grafana_service_account_token.tokens](https://registry.terraform.io/providers/grafana/grafana/4.25.0/docs/resources/service_account_token) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_org_ids"></a> [org\_ids](#input\_org\_ids) | Map of organization names to their IDs | `map(number)` | `{}` | no |
| <a name="input_service_accounts"></a> [service\_accounts](#input\_service\_accounts) | Service accounts configuration from YAML | `any` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_service_account_ids"></a> [service\_account\_ids](#output\_service\_account\_ids) | Map of service account names to their IDs |
| <a name="output_service_account_tokens"></a> [service\_account\_tokens](#output\_service\_account\_tokens) | Map of token names to their keys (sensitive) |
