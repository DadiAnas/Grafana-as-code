resource "grafana_team" "teams" {
  for_each = { for team in var.teams.teams : team.name => team }

  name   = each.value.name
  email  = try(each.value.email, null)
  org_id = try(var.org_ids[each.value.org], null)

  preferences {
    theme              = try(each.value.preferences.theme, null)
    home_dashboard_uid = try(each.value.preferences.home_dashboard_uid, null)
  }

  # Note: Team members need to exist first in Grafana
  # Members are managed separately if using Grafana with an identity provider
}
