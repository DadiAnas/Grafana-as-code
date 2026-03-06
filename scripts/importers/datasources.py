"""Import datasources from Grafana."""

from __future__ import annotations

import re
import sys
from datetime import datetime
from typing import Any

from .common import Colors, GrafanaClient, ImportContext, yaml_dump


def import_datasources(ctx: ImportContext) -> None:
    """Import datasources from all organizations."""
    print(f"{Colors.BLUE}[2/8]{Colors.NC} Importing datasources...")

    total_count = 0

    for org_id in ctx.org_ids:
        ctx.client.current_org_id = org_id
        org_name = ctx.org_map[org_id]

        datasources_resp = ctx.client.get("/api/datasources")
        if datasources_resp is None:
            print(
                f"  {Colors.YELLOW}⚠{Colors.NC} API request failed for org {org_name} (id={org_id}) — "
                "skipping datasources for this org (check auth/connectivity)",
                file=sys.stderr,
            )
            datasources_resp = []

        org_datasources = [_process_datasource(ds, org_name, org_id, ctx) for ds in datasources_resp]

        # Track terraform imports: grafana_data_source key = "org:uid", import ID = "orgId:uid"
        # Skip provisioned (readOnly) datasources — they can't be imported as resources
        # until the user removes them from Grafana's file-based provisioning.
        if not ctx.skip_tf_import:
            provisioned_names: list[str] = []
            for ds_entry in org_datasources:
                if ds_entry.pop("_provisioned", False):
                    provisioned_names.append(ds_entry["name"])
                    continue
                tf_key = f"{org_name}:{ds_entry['uid']}"
                ctx.tf_imports.append((
                    f'module.datasources.grafana_data_source.datasources["{tf_key}"]',
                    f"{org_id}:{ds_entry['uid']}",
                ))
            if provisioned_names:
                print(
                    f"  {Colors.YELLOW}⚠{Colors.NC} {len(provisioned_names)} provisioned (read-only) datasource(s) "
                    f"in {org_name} skipped from TF import: {', '.join(provisioned_names)}"
                )
                print(
                    f"    {Colors.DIM}Remove them from Grafana provisioning config, then re-run import "
                    f"or: terraform import 'module.datasources.grafana_data_source.datasources[\"<org>:<uid>\"]' '<orgId>:<uid>'{Colors.NC}"
                )
        else:
            # Still strip internal flag if skipping TF import
            for ds_entry in org_datasources:
                ds_entry.pop("_provisioned", None)

        # Always create the dir and file, even if empty
        org_dir = ctx.config_dir / "datasources" / org_name
        org_dir.mkdir(parents=True, exist_ok=True)
        output_file = org_dir / "datasources.yaml"
        with open(output_file, "w") as f:
            f.write(f"# Imported from {ctx.grafana_url} on {datetime.now().isoformat()}\n\n")
            f.write(yaml_dump({"datasources": org_datasources}))

        if org_datasources:
            print(f"  {Colors.GREEN}✓{Colors.NC} {len(org_datasources)} datasource(s) → envs/{ctx.env_name}/datasources/{org_name}/datasources.yaml")
        else:
            print(f"  {Colors.DIM}  0 datasources → envs/{ctx.env_name}/datasources/{org_name}/datasources.yaml (empty){Colors.NC}")
        total_count += len(org_datasources)

    ctx.client.current_org_id = None

    ctx.imported_count += 1


def _process_datasource(ds: dict[str, Any], org_name: str, org_id: int, ctx: ImportContext) -> dict[str, Any]:
    """Process a single datasource into YAML format."""
    json_data = ds.get("jsonData", {}).copy()
    secure_fields = ds.get("secureJsonFields", {})

    # Extract httpHeaderName*/httpHeaderValue* into http_headers
    http_headers: dict[str, str] = {}
    header_keys_to_remove: list[str] = []

    for k, v in list(json_data.items()):
        m = re.match(r"^httpHeaderName(\d+)$", k)
        if m:
            idx = m.group(1)
            header_name = str(v)
            header_keys_to_remove.append(k)
            val_key = f"httpHeaderValue{idx}"
            if val_key in json_data:
                http_headers[header_name] = str(json_data[val_key])
                header_keys_to_remove.append(val_key)
            else:
                http_headers[header_name] = ""
        elif re.match(r"^httpHeaderValue\d+$", k):
            header_keys_to_remove.append(k)

    for hk in set(header_keys_to_remove):
        json_data.pop(hk, None)

    entry: dict[str, Any] = {
        "name": ds["name"],
        "uid": ds.get("uid", ds["name"].lower().replace(" ", "-")),
        "type": ds["type"],
        "url": ds.get("url", ""),
        "org": org_name,
        "orgId": org_id,
        "access": ds.get("access", "proxy"),
        "is_default": ds.get("isDefault", False),
    }

    # Track provisioned (read-only) datasources
    if ds.get("readOnly"):
        entry["_provisioned"] = True

    if ds.get("basicAuth"):
        entry["basic_auth_enabled"] = True
        if ds.get("basicAuthUser"):
            entry["basic_auth_username"] = ds["basicAuthUser"]

    if ds.get("database"):
        entry["database_name"] = ds["database"]
    if ds.get("user"):
        entry["username"] = ds["user"]

    if json_data:
        entry["json_data"] = json_data

    if http_headers:
        entry["http_headers"] = http_headers

    # ── Detect secrets requiring Vault ───────────────────────────────────────
    secret_field_names: list[str] = sorted(secure_fields.keys())

    if ds.get("basicAuth") and "basicAuthPassword" not in secret_field_names:
        secret_field_names.append("basicAuthPassword")

    _DB_TYPES = {
        "postgres", "mysql", "mssql", "influxdb",
        "grafana-postgresql-datasource",
        "grafana-mysql-datasource",
        "grafana-mssql-datasource",
    }
    if ds.get("type") in _DB_TYPES and (ds.get("user") or ds.get("database")):
        if "password" not in secret_field_names:
            secret_field_names.append("password")

    _KNOWN_SECRET_JSON_KEYS = {
        "token", "apiKey", "accessKey", "secretKey", "clientSecret",
        "privateKey", "tlsClientKey", "tlsClientCert", "tlsCACert",
        "sigV4SecretKey", "oauthClientSecret",
    }
    for k, v in (json_data or {}).items():
        if k in _KNOWN_SECRET_JSON_KEYS and (v == "" or v is None):
            if k not in secret_field_names:
                secret_field_names.append(k)

    for header_name, header_val in http_headers.items():
        placeholder = f"httpHeader:{header_name}"
        if header_val == "" and placeholder not in secret_field_names:
            secret_field_names.append(placeholder)

    if secret_field_names:
        entry["use_vault"] = False
        vault_full_path = ctx.vault_path(ctx.env_name, "datasources", entry["name"])
        entry["vault_secret_fields"] = (
            f"{vault_full_path}: "
            + ", ".join(sorted(secret_field_names))
        )

    return entry
