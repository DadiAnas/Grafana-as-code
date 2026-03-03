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
| [grafana_dashboard.dashboards](https://registry.terraform.io/providers/grafana/grafana/4.25.0/docs/resources/dashboard) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_dashboards_path"></a> [dashboards\_path](#input\_dashboards\_path) | Path to the dashboards directory | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name | `string` | n/a | yes |
| <a name="input_folder_ids"></a> [folder\_ids](#input\_folder\_ids) | Map of folder UIDs to their IDs | `map(string)` | n/a | yes |
| <a name="input_folder_org_ids"></a> [folder\_org\_ids](#input\_folder\_org\_ids) | Map of folder UIDs to their organization IDs | `map(number)` | `{}` | no |
| <a name="input_exclude_folders"></a> [exclude\_folders](#input\_exclude\_folders) | List of folder paths (org/folder) to exclude from dashboard management | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_dashboard_ids"></a> [dashboard\_ids](#output\_dashboard\_ids) | Map of dashboard identifiers to their IDs |
| <a name="output_dashboard_uids"></a> [dashboard\_uids](#output\_dashboard\_uids) | Map of dashboard identifiers to their UIDs |
| <a name="output_dashboard_urls"></a> [dashboard\_urls](#output\_dashboard\_urls) | Map of dashboard identifiers to their URLs |
