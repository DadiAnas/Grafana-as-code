# Create organizations (skip id=1 which is the default org)
resource "grafana_organization" "orgs" {
  for_each = {
    for org in var.organizations.organizations : org.name => org
    if try(org.id, null) != 1
  }

  name    = each.value.name
  admins  = try(each.value.admins, [])
  editors = try(each.value.editors, [])
  viewers = try(each.value.viewers, [])

  # Org membership is managed by SSO group mappings at login time.
  # Ignore member lists so terraform apply doesn't revert SSO-assigned users.
  lifecycle {
    ignore_changes = [admins, editors, viewers]
  }
}

# Output for the default org
locals {
  default_org = [for org in var.organizations.organizations : org if try(org.id, null) == 1][0]
  
  # Combine created orgs with default org
  all_org_ids = merge(
    { for k, v in grafana_organization.orgs : k => v.org_id },
    { (local.default_org.name) = 1 }
  )
}
