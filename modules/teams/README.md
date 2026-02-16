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
| [grafana_team.teams](https://registry.terraform.io/providers/grafana/grafana/4.25.0/docs/resources/team) | resource |
| [grafana_team_external_group.team_sync](https://registry.terraform.io/providers/grafana/grafana/4.25.0/docs/resources/team_external_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| [org_ids](#input_org_ids) | Map of organization names to their IDs | `map(number)` | `{}` | no |
| [teams](#input_teams) | Teams configuration from YAML | `any` | n/a | yes |
| [enable_team_sync](#input_enable_team_sync) | Enable team external group sync (requires Grafana Enterprise or Cloud) | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| [team_ids](#output_team_ids) | Map of team composite keys to their full IDs (org_id:team_id format) |
| [team_numeric_ids](#output_team_numeric_ids) | Map of team composite keys to their numeric team IDs |
| [team_org_ids](#output_team_org_ids) | Map of team composite keys to their organization IDs |
| [team_details](#output_team_details) | Map of team composite keys to their details (team_id, org_id) for folder permissions |
