"""Import organizations from Grafana."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from .common import Colors, ImportContext, yaml_dump


def import_organizations(ctx: ImportContext) -> None:
    """Import organizations from Grafana."""
    print(f"{Colors.BLUE}[1/8]{Colors.NC} Importing organizations...")

    orgs = ctx.client.get("/api/orgs") or []
    if not orgs:
        print(f"  {Colors.DIM}  No organizations found{Colors.NC}")
        return

    # Build org mappings
    for org in orgs:
        ctx.org_map[org["id"]] = org["name"]
        ctx.org_ids.append(org["id"])

    # Generate YAML
    yaml_data = {
        "organizations": [
            {
                "name": org["name"],
                "id": org["id"],
                "admins": [],
                "editors": [],
                "viewers": [],
            }
            for org in orgs
        ]
    }

    output_file = ctx.config_dir / "organizations.yaml"
    with open(output_file, "w") as f:
        f.write(f"# Imported from {ctx.grafana_url} on {datetime.now().isoformat()}\n")
        f.write(f"# Organizations: {len(orgs)}\n\n")
        f.write(yaml_dump(yaml_data))

    print(f"  {Colors.GREEN}✓{Colors.NC} {len(orgs)} organization(s) → envs/{ctx.env_name}/organizations.yaml")
    ctx.imported_count += 1
