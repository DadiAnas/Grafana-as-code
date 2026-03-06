"""Import service accounts from Grafana."""

from __future__ import annotations

import sys
from datetime import datetime
from typing import Any

from .common import Colors, ImportContext, yaml_dump


def import_service_accounts(ctx: ImportContext) -> None:
    """Import service accounts from all organizations."""
    print(f"{Colors.BLUE}[5/8]{Colors.NC} Importing service accounts...")

    all_service_accounts: list[dict[str, Any]] = []

    for org_id in ctx.org_ids:
        ctx.client.current_org_id = org_id
        org_name = ctx.org_map[org_id]

        sa_resp = ctx.client.get("/api/serviceaccounts/search?perpage=1000")
        if sa_resp is None:
            print(
                f"  {Colors.YELLOW}⚠{Colors.NC} API request failed for org {org_name} (id={org_id}) — "
                "skipping service accounts for this org (check auth/connectivity)",
                file=sys.stderr,
            )
            sa_resp = {}
        service_accounts = sa_resp.get("serviceAccounts", [])

        for sa in service_accounts:
            sa_entry: dict[str, Any] = {
                "name": sa["name"],
                "role": sa.get("role", "Viewer"),
                "is_disabled": sa.get("isDisabled", False),
                "org": org_name,
                "orgId": org_id,
            }
            all_service_accounts.append(sa_entry)

            # Track terraform import
            if not ctx.skip_tf_import:
                sa_numeric_id = sa.get("id")
                if sa_numeric_id:
                    tf_key = f"{org_name}:{sa['name']}"
                    ctx.tf_imports.append((
                        f'module.service_accounts.grafana_service_account.service_accounts["{tf_key}"]',
                        f"{org_id}:{sa_numeric_id}",
                    ))

    ctx.client.current_org_id = None

    # Write per-org service account files
    sa_by_org: dict[str, list[dict[str, Any]]] = {}
    for sa_entry in all_service_accounts:
        org = sa_entry.get("org", "__no_org__")
        sa_by_org.setdefault(org, []).append(sa_entry)

    for org_id in ctx.org_ids:
        org_name = ctx.org_map[org_id]
        org_sas = sa_by_org.get(org_name, [])
        org_dir = ctx.config_dir / "service_accounts" / org_name
        org_dir.mkdir(parents=True, exist_ok=True)
        output_file = org_dir / "service_accounts.yaml"
        with open(output_file, "w") as f:
            f.write(f"# Imported from {ctx.grafana_url} on {datetime.now().isoformat()}\n\n")
            f.write(yaml_dump({"service_accounts": org_sas}))
        if org_sas:
            print(f"  {Colors.GREEN}✓{Colors.NC} {len(org_sas)} service account(s) → envs/{ctx.env_name}/service_accounts/{org_name}/service_accounts.yaml")
        else:
            print(f"  {Colors.DIM}  0 service accounts → envs/{ctx.env_name}/service_accounts/{org_name}/service_accounts.yaml (empty){Colors.NC}")

    ctx.imported_count += 1
