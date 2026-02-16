resource "grafana_team" "teams" {
  for_each = { for team in var.teams.teams : "${team.name}/${try(team.org, "Main Org.")}" => team }

  name   = each.value.name
  email  = try(each.value.email, null)
  org_id = try(var.org_ids[each.value.org], null) != null ? var.org_ids[each.value.org] : try(tonumber(each.value.orgId), null)

  preferences {
    theme              = try(each.value.preferences.theme, null)
    home_dashboard_uid = try(each.value.preferences.home_dashboard_uid, null)
  }

  # Team membership is managed externally via `make team-sync` (Keycloak → Grafana).
  # Ignore members so terraform apply doesn't revert synced membership.
  lifecycle {
    ignore_changes = [members]
  }
}

# Team Sync — maps external IdP/SSO groups to Grafana teams
# Enterprise/Cloud: uses grafana_team_external_group resource (enable_team_sync = true)
# OSS: run standalone via `make team-sync` — NOT managed by Terraform
#
# Configure external_groups on each team in teams.yaml:
#   - name: "Backend Team"
#     external_groups:
#       - "keycloak-backend-devs"

# --- Enterprise/Cloud path ---
resource "grafana_team_external_group" "team_sync" {
  for_each = var.enable_team_sync ? {
    for team in var.teams.teams : "${team.name}/${try(team.org, "Main Org.")}" => team
    if try(length(team.external_groups), 0) > 0
  } : {}

  team_id = grafana_team.teams[each.key].id
  groups  = each.value.external_groups
}
