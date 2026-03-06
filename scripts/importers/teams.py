"""Import teams from Grafana."""

from __future__ import annotations

import sys
from datetime import datetime
from typing import Any

from .common import Colors, ImportContext, yaml_dump


def import_teams(ctx: ImportContext) -> None:
    """Import teams from all organizations."""
    print(f"{Colors.BLUE}[4/8]{Colors.NC} Importing teams...")

    all_teams: list[dict[str, Any]] = []

    for org_id in ctx.org_ids:
        ctx.client.current_org_id = org_id
        org_name = ctx.org_map[org_id]

        teams_resp = ctx.client.get("/api/teams/search?perpage=1000")
        if teams_resp is None:
            print(
                f"  {Colors.YELLOW}⚠{Colors.NC} API request failed for org {org_name} (id={org_id}) — "
                "skipping teams for this org (check auth/connectivity)",
                file=sys.stderr,
            )
            teams_resp = {}
        teams = teams_resp.get("teams", [])

        for team in teams:
            team_entry: dict[str, Any] = {
                "name": team["name"],
                "org": org_name,
                "orgId": org_id,
                "members": [],
            }

            if team.get("email"):
                team_entry["email"] = team["email"]

            # Try to get external group mappings (Enterprise/Cloud only)
            groups_resp = ctx.client.get(f"/api/teams/{team['id']}/groups")
            if groups_resp and isinstance(groups_resp, list):
                ext_groups = [g.get("groupId", "") for g in groups_resp if g.get("groupId")]
                if ext_groups:
                    team_entry["external_groups"] = ext_groups

            all_teams.append(team_entry)

            # Track terraform import
            if not ctx.skip_tf_import:
                team_numeric_id = team.get("id")
                if team_numeric_id:
                    tf_key = f"{team['name']}/{org_name}"
                    ctx.tf_imports.append((
                        f'module.teams.grafana_team.teams["{tf_key}"]',
                        f"{org_id}:{team_numeric_id}",
                    ))

    ctx.client.current_org_id = None

    # Write per-org team files
    teams_by_org: dict[str, list[dict[str, Any]]] = {}
    for team_entry in all_teams:
        org = team_entry.get("org", "__no_org__")
        teams_by_org.setdefault(org, []).append(team_entry)

    for org_id in ctx.org_ids:
        org_name = ctx.org_map[org_id]
        org_teams = teams_by_org.get(org_name, [])
        org_dir = ctx.config_dir / "teams" / org_name
        org_dir.mkdir(parents=True, exist_ok=True)
        output_file = org_dir / "teams.yaml"
        with open(output_file, "w") as f:
            f.write(f"# Imported from {ctx.grafana_url} on {datetime.now().isoformat()}\n\n")
            f.write(yaml_dump({"teams": org_teams}))
        if org_teams:
            print(f"  {Colors.GREEN}✓{Colors.NC} {len(org_teams)} team(s) → envs/{ctx.env_name}/teams/{org_name}/teams.yaml")
        else:
            print(f"  {Colors.DIM}  0 teams → envs/{ctx.env_name}/teams/{org_name}/teams.yaml (empty){Colors.NC}")

    ctx.imported_count += 1
