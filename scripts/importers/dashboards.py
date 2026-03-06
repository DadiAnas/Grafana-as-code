"""Import dashboards from Grafana."""

from __future__ import annotations

import json
from typing import Any

from .common import Colors, ImportContext, safe_filename


def import_dashboards(ctx: ImportContext) -> None:
    """Import dashboards from all organizations."""
    if not ctx.import_dashboards:
        print(f"{Colors.BLUE}[7/8]{Colors.NC} {Colors.DIM}Skipping dashboards (--no-dashboards){Colors.NC}")
        return

    print(f"{Colors.BLUE}[7/8]{Colors.NC} Importing dashboards...")

    dash_dir = ctx.output_dir / "envs" / ctx.env_name / "dashboards"

    for org_id in ctx.org_ids:
        ctx.client.current_org_id = org_id
        org_name = ctx.org_map[org_id]

        org_dash_dir = dash_dir / org_name
        org_dash_dir.mkdir(parents=True, exist_ok=True)
        general_dir = org_dash_dir / "general"
        general_dir.mkdir(parents=True, exist_ok=True)
        for d in (org_dash_dir, general_dir):
            gitkeep = d / ".gitkeep"
            if not gitkeep.exists():
                gitkeep.touch()

        search_results = ctx.client.get("/api/search?type=dash-db&limit=5000") or []
        if not search_results:
            print(f"  {Colors.DIM}  0 dashboards for {org_name} (empty directory created){Colors.NC}")
            continue

        for dash in search_results:
            uid = dash.get("uid", "")
            folder_uid = dash.get("folderUid", "general") or "general"
            title = dash.get("title", "unknown")

            slug_folder_path = ctx.folder_path_map.get(folder_uid, ctx.folder_uid_map.get(folder_uid, folder_uid))
            safe_title = safe_filename(title)

            folder_path = dash_dir / org_name / slug_folder_path
            folder_path.mkdir(parents=True, exist_ok=True)

            dash_data = ctx.client.get(f"/api/dashboards/uid/{uid}")
            if dash_data:
                dashboard = dash_data.get("dashboard", {})
                dashboard.pop("id", None)
                dashboard.pop("version", None)

                output_file = folder_path / f"{safe_title}.json"
                with open(output_file, "w") as f:
                    json.dump(dashboard, f, indent=2)

                if not ctx.skip_tf_import:
                    dashboard_uid = dashboard.get("uid", uid)
                    tf_key = f"{org_name}-{slug_folder_path.replace('/', '-')}-{safe_title}.json"
                    ctx.tf_imports.append((
                        f'module.dashboards.grafana_dashboard.dashboards["{tf_key}"]',
                        f"{org_id}:{dashboard_uid}",
                    ))

                print(f"  {Colors.GREEN}✓{Colors.NC} {org_name}/{slug_folder_path}/{safe_title}.json")

    ctx.client.current_org_id = None
    print(f"  {Colors.GREEN}✓{Colors.NC} Exported dashboards to envs/{ctx.env_name}/dashboards/")
    ctx.imported_count += 1
