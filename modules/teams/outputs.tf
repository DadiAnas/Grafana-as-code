output "team_ids" {
  description = "Map of team names to their IDs"
  value       = { for k, v in grafana_team.teams : k => v.id }
}
