output "organization_ids" {
  description = "Map of organization names to their IDs"
  value       = local.all_org_ids
}

output "organizations" {
  description = "Created organizations"
  value       = grafana_organization.orgs
}
