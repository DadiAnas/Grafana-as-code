output "contact_point_names" {
  description = "List of contact point names"
  value       = [for cp in grafana_contact_point.contact_points : cp.name]
}

output "rule_group_names" {
  description = "List of rule group names"
  value       = [for rg in grafana_rule_group.rule_groups : rg.name]
}

output "alert_rule_count" {
  description = "Total number of alert rules deployed"
  value       = length(flatten([for rg in grafana_rule_group.rule_groups : rg.rule]))
}
