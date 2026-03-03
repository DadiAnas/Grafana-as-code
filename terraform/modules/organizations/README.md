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
| [grafana_organization.orgs](https://registry.terraform.io/providers/grafana/grafana/4.25.0/docs/resources/organization) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_organizations"></a> [organizations](#input\_organizations) | Organizations configuration from YAML | `any` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_organization_ids"></a> [organization\_ids](#output\_organization\_ids) | Map of organization names to their IDs |
| <a name="output_organizations"></a> [organizations](#output\_organizations) | Created organizations |
