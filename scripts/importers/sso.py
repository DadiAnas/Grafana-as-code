"""Import SSO settings from Grafana."""

from __future__ import annotations

import json
import sys
from typing import Any

from .common import Colors, ImportContext, _sanitize_string, parse_json_str, yaml_dump


def import_sso(ctx: ImportContext) -> None:
    """Import SSO settings."""
    print(f"{Colors.BLUE}[8/8]{Colors.NC} Importing SSO settings...")

    sso_settings = ctx.client.get("/api/v1/sso-settings") or []

    # Find enabled provider (prefer generic_oauth)
    enabled_provider = None
    for p in sso_settings:
        if p.get("settings", {}).get("enabled", False):
            if p.get("provider") == "generic_oauth" or enabled_provider is None:
                enabled_provider = p

    output_file = ctx.config_dir / "sso.yaml"
    with open(output_file, "w") as f:
        f.write("# Imported from Grafana SSO settings\n")
        f.write("#\n")
        f.write("# This file follows the project format expected by modules/sso.\n")
        vault_sso_path = ctx.vault_path(ctx.env_name, "sso", "keycloak")
        f.write(f"# Client secret Vault path: {vault_sso_path}\n\n")

        if enabled_provider is None:
            f.write(yaml_dump({"sso": {"enabled": False}}))
            print(f"  {Colors.DIM}  SSO disabled → envs/{ctx.env_name}/sso.yaml{Colors.NC}")
        else:
            sso_config = _process_sso_settings(enabled_provider, ctx.org_map)
            f.write(yaml_dump({"sso": sso_config}))
            print(f"  {Colors.GREEN}✓{Colors.NC} SSO config (enabled) → envs/{ctx.env_name}/sso.yaml")

    ctx.imported_count += 1

    # Create keycloak.yaml if it doesn't exist
    keycloak_file = ctx.config_dir / "keycloak.yaml"
    if not keycloak_file.exists():
        keycloak_config = {
            "keycloak": {
                "enabled": False,
                "realm_id": "master",
                "client_id": "grafana",
                "root_url": ctx.grafana_url,
            }
        }
        with open(keycloak_file, "w") as f:
            f.write("# Keycloak configuration — must be configured manually\n\n")
            f.write(yaml_dump(keycloak_config))


def _process_sso_settings(provider: dict[str, Any], org_map: dict[int, str]) -> dict[str, Any]:
    """Process SSO provider settings into YAML format."""
    s = provider.get("settings", {})
    provider_type = provider.get("provider", "generic_oauth")

    config: dict[str, Any] = {
        "enabled": True,
        "name": s.get("name", provider_type),
        "auth_url": s.get("authUrl", ""),
        "token_url": s.get("tokenUrl", ""),
        "api_url": s.get("apiUrl", ""),
        "client_id": s.get("clientId", ""),
        "allow_sign_up": s.get("allowSignUp", True),
        "auto_login": s.get("autoLogin", False),
        "scopes": parse_json_str(s.get("scopes", "openid profile email groups"), " "),
        "use_pkce": s.get("usePkce", True),
        "use_refresh_token": s.get("useRefreshToken", True),
        "role_attribute_strict": s.get("roleAttributeStrict", False),
        "skip_org_role_sync": s.get("skipOrgRoleSync", False),
    }

    if s.get("roleAttributePath"):
        config["role_attribute_path"] = s["roleAttributePath"]
    if s.get("groupsAttributePath"):
        config["groups_attribute_path"] = s["groupsAttributePath"]
    if s.get("orgAttributePath"):
        config["org_attribute_path"] = s["orgAttributePath"]

    ag = s.get("allowedGroups", "")
    if ag:
        config["allowed_groups"] = parse_json_str(ag, ",")

    org_mapping_str = s.get("orgMapping", "")
    if org_mapping_str:
        config["groups"] = _process_org_mapping(org_mapping_str, org_map)

    if s.get("teamsUrl"):
        config["teams_url"] = s["teamsUrl"]
    if s.get("teamIdsAttributePath"):
        config["team_ids_attribute_path"] = s["teamIdsAttributePath"]
    if s.get("signoutRedirectUrl"):
        config["signout_redirect_url"] = s["signoutRedirectUrl"]

    return config


def _process_org_mapping(org_mapping_str: str, org_map: dict[int, str]) -> list[dict[str, Any]]:
    """Process org_mapping string into groups format."""
    if org_mapping_str.startswith("["):
        try:
            mappings = [m.strip() for m in json.loads(org_mapping_str) if m.strip()]
        except (json.JSONDecodeError, TypeError):
            mappings = [m.strip() for m in org_mapping_str.strip().replace("\\n", "\n").split("\n") if m.strip()]
    else:
        mappings = [m.strip() for m in org_mapping_str.strip().replace("\\n", "\n").split("\n") if m.strip()]

    org_name_lookup = {str(k): v for k, v in org_map.items()}
    all_org_ids = set(org_name_lookup.keys())

    groups: dict[str, list[dict[str, Any]]] = {}
    group_order: list[str] = []

    for m in mappings:
        parts = m.split(":")
        if len(parts) >= 3:
            group_name = _sanitize_string(parts[0])
            org_id = _sanitize_string(parts[1])
            role = _sanitize_string(parts[2])
        elif len(parts) == 2 and parts[1].startswith("*"):
            group_name = _sanitize_string(parts[0])
            org_id = "*"
            role = _sanitize_string(parts[1][1:])
            print(f'  {Colors.YELLOW}⚠{Colors.NC} Fixed malformed org_mapping: "{m}" → "{group_name}:*:{role}"', file=sys.stderr)
        else:
            print(f'  {Colors.YELLOW}⚠{Colors.NC} Skipping malformed org_mapping entry: "{m}"', file=sys.stderr)
            continue

        if group_name not in groups:
            groups[group_name] = []
            group_order.append(group_name)

        entry: dict[str, Any] = {"role": role}
        if org_id == "*":
            entry["orgId"] = "*"
        else:
            entry["orgId"] = int(org_id) if org_id.isdigit() else org_id
            entry["_org_id"] = org_id

        groups[group_name].append(entry)

    # Collapse: if a group maps to ALL orgs with the same role, use org: "*"
    for group_name in group_order:
        mappings_list = groups[group_name]
        if any(m.get("orgId") == "*" for m in mappings_list):
            continue

        role_counts: dict[str, list[dict[str, Any]]] = {}
        for m in mappings_list:
            role_counts.setdefault(m["role"], []).append(m)

        for role, role_mappings in role_counts.items():
            covered_ids = {m["_org_id"] for m in role_mappings if "_org_id" in m}
            if len(all_org_ids) > 1 and covered_ids >= all_org_ids:
                remaining = [m for m in mappings_list if m["role"] != role]
                remaining.insert(0, {"orgId": "*", "role": role})
                groups[group_name] = remaining
                break

    result: list[dict[str, Any]] = []
    for group_name in group_order:
        group_entry: dict[str, Any] = {"name": group_name}
        if group_name == "*":
            group_entry["wildcard_group"] = True
        group_entry["org_mappings"] = [
            {"orgId": m["orgId"], "role": m["role"]} for m in groups[group_name]
        ]
        result.append(group_entry)

    return result
