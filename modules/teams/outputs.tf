output "team_ids" {
  description = "Map of team names to their full IDs (org_id:team_id format)"
  value       = { for k, v in grafana_team.teams : k => v.id }
}

output "team_numeric_ids" {
  description = "Map of team names to their numeric team IDs (for folder permissions)"
  value       = { for k, v in grafana_team.teams : k => v.team_id }
}

output "team_org_ids" {
  description = "Map of team names to their organization IDs"
  value       = { for k, v in grafana_team.teams : k => v.org_id }
}

# Combined output for folder permissions - includes team_id and org_id
output "team_details" {
  description = "Map of team names to their details (team_id, org_id) for folder permissions"
  value = {
    for k, v in grafana_team.teams : k => {
      team_id = v.team_id
      org_id  = v.org_id
    }
  }
}
