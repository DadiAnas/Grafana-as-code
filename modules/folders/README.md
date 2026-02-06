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
| [grafana_folder.folders](https://registry.terraform.io/providers/grafana/grafana/4.25.0/docs/resources/folder) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_folders"></a> [folders](#input\_folders) | Folders configuration from YAML | `any` | n/a | yes |
| <a name="input_org_ids"></a> [org\_ids](#input\_org\_ids) | Map of organization names to their IDs | `map(number)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_folder_ids"></a> [folder\_ids](#output\_folder\_ids) | Map of folder UIDs to their IDs |
| <a name="output_folder_uids"></a> [folder\_uids](#output\_folder\_uids) | Map of folder names to their UIDs |
