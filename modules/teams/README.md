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

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_org_ids"></a> [org\_ids](#input\_org\_ids) | Map of organization names to their IDs | `map(number)` | `{}` | no |
| <a name="input_teams"></a> [teams](#input\_teams) | Teams configuration from YAML | `any` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_team_ids"></a> [team\_ids](#output\_team\_ids) | Map of team names to their IDs |
