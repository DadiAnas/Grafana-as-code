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
| [grafana_contact_point.contact_points](https://registry.terraform.io/providers/grafana/grafana/4.25.0/docs/resources/contact_point) | resource |
| [grafana_notification_policy.policy](https://registry.terraform.io/providers/grafana/grafana/4.25.0/docs/resources/notification_policy) | resource |
| [grafana_rule_group.rule_groups](https://registry.terraform.io/providers/grafana/grafana/4.25.0/docs/resources/rule_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alert_rules"></a> [alert\_rules](#input\_alert\_rules) | Alert rules configuration from YAML | `any` | n/a | yes |
| <a name="input_contact_points"></a> [contact\_points](#input\_contact\_points) | Contact points configuration from YAML | `any` | n/a | yes |
| <a name="input_folder_ids"></a> [folder\_ids](#input\_folder\_ids) | Map of folder UIDs to their IDs | `map(string)` | n/a | yes |
| <a name="input_notification_policies"></a> [notification\_policies](#input\_notification\_policies) | Notification policies configuration from YAML | `any` | n/a | yes |
| <a name="input_vault_credentials"></a> [vault\_credentials](#input\_vault\_credentials) | Map of contact point names to their credentials from Vault | `map(map(string))` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_contact_point_names"></a> [contact\_point\_names](#output\_contact\_point\_names) | List of contact point names |
| <a name="output_rule_group_names"></a> [rule\_group\_names](#output\_rule\_group\_names) | List of rule group names |
