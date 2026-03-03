#!/usr/bin/env python3
"""
Import from Grafana — Generate YAML configs from an existing instance.

Connects to a running Grafana instance and generates YAML configuration
files that can be used with this Terraform framework.

Usage:
    python scripts/import_from_grafana.py prod \
        --grafana-url=https://grafana.example.com \
        --auth=admin:admin
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

import requests
import yaml


# =============================================================================
# ANSI Colors
# =============================================================================
class Colors:
    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    BLUE = "\033[0;34m"
    CYAN = "\033[0;36m"
    DIM = "\033[2m"
    BOLD = "\033[1m"
    NC = "\033[0m"  # No Color


# =============================================================================
# YAML Helpers
# =============================================================================
class QuotedDumper(yaml.SafeDumper):
    """YAML dumper that doesn't use anchors/aliases and quotes string values."""

    def ignore_aliases(self, data: Any) -> bool:
        return True

    def represent_mapping(self, tag: str, mapping: Any, flow_style: bool | None = None) -> yaml.MappingNode:
        """Override to avoid quoting keys."""
        value: list[tuple[yaml.Node, yaml.Node]] = []
        node = yaml.MappingNode(tag, value, flow_style=flow_style)
        if self.alias_key is not None:
            self.represented_objects[self.alias_key] = node
        best_style = True
        if hasattr(mapping, "items"):
            mapping = list(mapping.items())
        for item_key, item_value in mapping:
            # For keys, use plain representation (no quotes)
            if isinstance(item_key, str):
                node_key = self.represent_scalar("tag:yaml.org,2002:str", item_key)
            else:
                node_key = self.represent_data(item_key)
            node_value = self.represent_data(item_value)
            if not (isinstance(node_key, yaml.ScalarNode) and not node_key.style):
                best_style = False
            if not (isinstance(node_value, yaml.ScalarNode) and not node_value.style):
                best_style = False
            value.append((node_key, node_value))
        if flow_style is None:
            if self.default_flow_style is not None:
                node.flow_style = self.default_flow_style
            else:
                node.flow_style = best_style
        return node


def _quoted_str_representer(dumper: yaml.Dumper, data: str) -> yaml.ScalarNode:
    """Represent all string values with double quotes for consistency."""
    return dumper.represent_scalar("tag:yaml.org,2002:str", data, style='"')


QuotedDumper.add_representer(str, _quoted_str_representer)


def yaml_dump(data: Any, **kwargs: Any) -> str:
    """Dump data to YAML without aliases, with proper string quoting."""
    return yaml.dump(data, Dumper=QuotedDumper, default_flow_style=False, sort_keys=False, **kwargs)


# =============================================================================
# Data Classes
# =============================================================================
@dataclass
class GrafanaClient:
    """Grafana API client."""

    url: str
    auth: str
    current_org_id: int | None = None
    timeout: int = 15

    def _get_auth(self) -> tuple[str, str] | dict[str, str]:
        """Return auth tuple or headers dict."""
        if ":" in self.auth:
            user, password = self.auth.split(":", 1)
            return (user, password)
        return {}

    def _get_headers(self) -> dict[str, str]:
        """Return request headers."""
        headers: dict[str, str] = {}
        if ":" not in self.auth:
            headers["Authorization"] = f"Bearer {self.auth}"
        if self.current_org_id:
            headers["X-Grafana-Org-Id"] = str(self.current_org_id)
        return headers

    def get(self, endpoint: str) -> Any:
        """Make a GET request to the Grafana API."""
        url = f"{self.url}{endpoint}"
        auth = self._get_auth() if isinstance(self._get_auth(), tuple) else None
        headers = self._get_headers()

        try:
            resp = requests.get(url, auth=auth, headers=headers, timeout=self.timeout)
            resp.raise_for_status()
            return resp.json()
        except requests.RequestException:
            return None

    def health(self) -> dict[str, Any] | None:
        """Check Grafana health."""
        return self.get("/api/health")


@dataclass
class ImportContext:
    """Context for the import operation."""

    env_name: str
    grafana_url: str
    client: GrafanaClient
    output_dir: Path
    config_dir: Path
    import_dashboards: bool = True

    # Mappings built during import
    org_map: dict[int, str] = field(default_factory=dict)  # org_id -> org_name
    org_ids: list[int] = field(default_factory=list)
    folder_uid_map: dict[str, str] = field(default_factory=dict)  # old_uid -> slug_uid

    imported_count: int = 0


# =============================================================================
# Utility Functions
# =============================================================================
def slugify(title: str) -> str:
    """Convert a title to a clean, filesystem-safe slug."""
    s = title.lower().strip()
    s = re.sub(r"[^a-z0-9\s-]", "", s)  # Remove special chars
    s = re.sub(r"[\s_]+", "-", s)  # Spaces/underscores → hyphens
    s = re.sub(r"-+", "-", s)  # Collapse multiple hyphens
    s = s.strip("-")
    return s or "folder"


def parse_json_str(val: str, join_char: str = " ") -> str:
    """Parse a value that may be a JSON array string or a plain string."""
    if isinstance(val, str) and val.startswith("["):
        try:
            items = json.loads(val)
            if isinstance(items, list):
                return join_char.join(str(i) for i in items)
        except (json.JSONDecodeError, TypeError):
            pass
    return val


def safe_filename(title: str) -> str:
    """Make a string safe for use as a filename."""
    return re.sub(r"[\/\\]", "-", title)


# =============================================================================
# Import Functions
# =============================================================================
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


def import_datasources(ctx: ImportContext) -> None:
    """Import datasources from all organizations."""
    print(f"{Colors.BLUE}[2/8]{Colors.NC} Importing datasources...")

    all_datasources: list[dict[str, Any]] = []

    for org_id in ctx.org_ids:
        ctx.client.current_org_id = org_id
        org_name = ctx.org_map[org_id]

        datasources = ctx.client.get("/api/datasources") or []
        for ds in datasources:
            ds_entry = _process_datasource(ds, org_name, org_id)
            all_datasources.append(ds_entry)

    ctx.client.current_org_id = None

    if not all_datasources:
        print(f"  {Colors.DIM}  No datasources found{Colors.NC}")
        return

    output_file = ctx.config_dir / "datasources.yaml"
    with open(output_file, "w") as f:
        f.write(f"# Imported from {ctx.grafana_url} on {datetime.now().isoformat()}\n\n")
        f.write(yaml_dump({"datasources": all_datasources}))

    print(f"  {Colors.GREEN}✓{Colors.NC} {len(all_datasources)} datasource(s) across {len(ctx.org_ids)} org(s) → envs/{ctx.env_name}/datasources.yaml")
    ctx.imported_count += 1


def _process_datasource(ds: dict[str, Any], org_name: str, org_id: int) -> dict[str, Any]:
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
        "access": ds.get("access", "proxy"),
        "is_default": ds.get("isDefault", False),
    }

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

    # Add comment about secure fields
    if secure_fields:
        entry["_comment_secure_fields"] = f"Secure fields detected: {list(secure_fields.keys())}. Configure via Vault."

    return entry


def import_folders(ctx: ImportContext) -> None:
    """Import folders from all organizations."""
    print(f"{Colors.BLUE}[3/8]{Colors.NC} Importing folders...")

    # Phase 1: Build global UID mapping
    for org_id in ctx.org_ids:
        ctx.client.current_org_id = org_id
        folders = ctx.client.get("/api/folders?limit=1000") or []

        used_slugs: set[str] = set()
        top_level = [f for f in folders if not f.get("parentUid")]
        children = [f for f in folders if f.get("parentUid")]

        for folder in top_level + children:
            old_uid = folder["uid"]
            base_slug = slugify(folder["title"])
            slug = base_slug
            counter = 1
            while slug in used_slugs:
                counter += 1
                slug = f"{base_slug}-{counter}"
            used_slugs.add(slug)
            ctx.folder_uid_map[old_uid] = slug

    ctx.client.current_org_id = None

    # Phase 2: Generate folders.yaml
    all_folders: list[dict[str, Any]] = []
    total_folders = 0

    for org_id in ctx.org_ids:
        ctx.client.current_org_id = org_id
        org_name = ctx.org_map[org_id]

        folders = ctx.client.get("/api/folders?limit=1000") or []
        if not folders:
            continue

        # Get teams and users for permission mapping
        teams_data = ctx.client.get("/api/teams/search?perpage=1000") or {}
        team_map = {t["id"]: t["name"] for t in teams_data.get("teams", [])}

        users_data = ctx.client.get("/api/org/users?perpage=1000") or []
        user_map = {u["userId"]: u["login"] for u in users_data}

        for folder in folders:
            old_uid = folder["uid"]
            new_uid = ctx.folder_uid_map.get(old_uid, old_uid)
            parent_old = folder.get("parentUid", "")
            parent_new = ctx.folder_uid_map.get(parent_old, parent_old) if parent_old else ""

            folder_entry: dict[str, Any] = {
                "title": folder["title"],
                "uid": new_uid,
                "_comment_original_uid": old_uid,
                "org": org_name,
            }

            if parent_new:
                folder_entry["parent_uid"] = parent_new

            # Fetch permissions
            perms = ctx.client.get(f"/api/folders/{old_uid}/permissions") or []
            explicit_perms = [p for p in perms if not p.get("inherited", False) and p.get("permission", 0) > 0]

            perm_names = {1: "View", 2: "Edit", 4: "Admin"}
            permissions: list[dict[str, str]] = []

            for p in explicit_perms:
                perm_str = perm_names.get(p["permission"], str(p["permission"]))
                if p.get("teamId", 0) > 0:
                    team_name = team_map.get(p["teamId"], f"team-{p['teamId']}")
                    permissions.append({"team": team_name, "permission": perm_str})
                elif p.get("userId", 0) > 0:
                    user_login = user_map.get(p["userId"], f"user-{p['userId']}")
                    permissions.append({"user": user_login, "permission": perm_str})
                elif p.get("role", ""):
                    permissions.append({"role": p["role"], "permission": perm_str})

            folder_entry["permissions"] = permissions
            all_folders.append(folder_entry)
            total_folders += 1

    ctx.client.current_org_id = None

    # Phase 3: Create dashboard directories
    dash_base = ctx.output_dir / "envs" / ctx.env_name / "dashboards"
    for org_id in ctx.org_ids:
        ctx.client.current_org_id = org_id
        org_name = ctx.org_map[org_id]

        folders = ctx.client.get("/api/folders?limit=1000") or []
        for folder in folders:
            slug_uid = ctx.folder_uid_map.get(folder["uid"], folder["uid"])
            folder_path = dash_base / org_name / slug_uid
            folder_path.mkdir(parents=True, exist_ok=True)
            gitkeep = folder_path / ".gitkeep"
            if not gitkeep.exists():
                gitkeep.touch()

    ctx.client.current_org_id = None

    if not all_folders:
        print(f"  {Colors.DIM}  No folders found{Colors.NC}")
        return

    output_file = ctx.config_dir / "folders.yaml"
    with open(output_file, "w") as f:
        f.write(f"# Imported from {ctx.grafana_url} on {datetime.now().isoformat()}\n")
        f.write("# NOTE: Folder UIDs have been slugified from the original random Grafana UIDs\n")
        f.write("#       for better readability in both YAML config and directory structure.\n\n")
        f.write(yaml_dump({"folders": all_folders}))

    print(f"  {Colors.GREEN}✓{Colors.NC} {total_folders} folder(s) across {len(ctx.org_ids)} org(s) → envs/{ctx.env_name}/folders.yaml")
    print(f"  {Colors.GREEN}✓{Colors.NC} Created {total_folders} folder directories under envs/{ctx.env_name}/dashboards/")
    ctx.imported_count += 1


def import_teams(ctx: ImportContext) -> None:
    """Import teams from all organizations."""
    print(f"{Colors.BLUE}[4/8]{Colors.NC} Importing teams...")

    all_teams: list[dict[str, Any]] = []

    for org_id in ctx.org_ids:
        ctx.client.current_org_id = org_id
        org_name = ctx.org_map[org_id]

        teams_data = ctx.client.get("/api/teams/search?perpage=1000") or {}
        teams = teams_data.get("teams", [])

        for team in teams:
            team_entry: dict[str, Any] = {
                "name": team["name"],
                "org": org_name,
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

    ctx.client.current_org_id = None

    if not all_teams:
        print(f"  {Colors.DIM}  No teams found{Colors.NC}")
        return

    output_file = ctx.config_dir / "teams.yaml"
    with open(output_file, "w") as f:
        f.write(f"# Imported from {ctx.grafana_url} on {datetime.now().isoformat()}\n\n")
        f.write(yaml_dump({"teams": all_teams}))

    print(f"  {Colors.GREEN}✓{Colors.NC} {len(all_teams)} team(s) across {len(ctx.org_ids)} org(s) → envs/{ctx.env_name}/teams.yaml")
    ctx.imported_count += 1


def import_service_accounts(ctx: ImportContext) -> None:
    """Import service accounts from all organizations."""
    print(f"{Colors.BLUE}[5/8]{Colors.NC} Importing service accounts...")

    all_service_accounts: list[dict[str, Any]] = []

    for org_id in ctx.org_ids:
        ctx.client.current_org_id = org_id
        org_name = ctx.org_map[org_id]

        sa_data = ctx.client.get("/api/serviceaccounts/search?perpage=1000") or {}
        service_accounts = sa_data.get("serviceAccounts", [])

        for sa in service_accounts:
            sa_entry: dict[str, Any] = {
                "name": sa["name"],
                "role": sa.get("role", "Viewer"),
                "is_disabled": sa.get("isDisabled", False),
                "org": org_name,
            }
            all_service_accounts.append(sa_entry)

    ctx.client.current_org_id = None

    if not all_service_accounts:
        print(f"  {Colors.DIM}  No service accounts found{Colors.NC}")
        return

    output_file = ctx.config_dir / "service_accounts.yaml"
    with open(output_file, "w") as f:
        f.write(f"# Imported from {ctx.grafana_url} on {datetime.now().isoformat()}\n\n")
        f.write(yaml_dump({"service_accounts": all_service_accounts}))

    print(f"  {Colors.GREEN}✓{Colors.NC} {len(all_service_accounts)} service account(s) across {len(ctx.org_ids)} org(s) → envs/{ctx.env_name}/service_accounts.yaml")
    ctx.imported_count += 1


def import_alerting(ctx: ImportContext) -> None:
    """Import alerting configuration (contact points, rules, policies)."""
    print(f"{Colors.BLUE}[6/8]{Colors.NC} Importing alerting configuration...")

    alerting_dir = ctx.config_dir / "alerting"
    alerting_dir.mkdir(parents=True, exist_ok=True)

    # Contact Points
    all_contact_points: list[dict[str, Any]] = []
    total_cp = 0

    for org_id in ctx.org_ids:
        ctx.client.current_org_id = org_id
        org_name = ctx.org_map[org_id]

        contact_points = ctx.client.get("/api/v1/provisioning/contact-points") or []
        if not contact_points:
            continue

        # Group by name
        grouped: dict[str, dict[str, Any]] = {}
        for cp in contact_points:
            name = cp["name"]
            if name not in grouped:
                grouped[name] = {"name": name, "org": org_name, "receivers": []}

            recv: dict[str, Any] = {"type": cp["type"]}
            settings = cp.get("settings", {})
            if settings:
                recv["settings"] = settings
            dis_resolve = cp.get("disableResolveMessage")
            if dis_resolve is not None:
                recv["disableResolveMessage"] = dis_resolve
            grouped[name]["receivers"].append(recv)
            total_cp += 1

        all_contact_points.extend(grouped.values())

    ctx.client.current_org_id = None

    if total_cp > 0:
        output_file = alerting_dir / "contact_points.yaml"
        with open(output_file, "w") as f:
            f.write(f"# Imported from {ctx.grafana_url} on {datetime.now().isoformat()}\n\n")
            f.write(yaml_dump({"contactPoints": all_contact_points}))
        print(f"  {Colors.GREEN}✓{Colors.NC} {total_cp} contact point(s) across {len(ctx.org_ids)} org(s)")
        ctx.imported_count += 1

    # Alert Rules
    all_groups: list[dict[str, Any]] = []
    total_ar = 0

    for org_id in ctx.org_ids:
        ctx.client.current_org_id = org_id
        org_name = ctx.org_map[org_id]

        rules = ctx.client.get("/api/v1/provisioning/alert-rules") or []
        if not rules:
            continue

        groups: dict[str, dict[str, Any]] = {}
        for rule in rules:
            folder_raw = rule.get("folderUID", "general")
            folder = ctx.folder_uid_map.get(folder_raw, folder_raw)
            group_name = rule.get("ruleGroup", "default")
            key = f"{folder}/{group_name}"

            if key not in groups:
                groups[key] = {
                    "name": group_name,
                    "folder": folder,
                    "org": org_name,
                    "interval": "1m",
                    "rules": [],
                }

            r_data = {
                "title": rule.get("title", rule.get("name", "Alert")),
                "condition": rule.get("condition", ""),
                "for": rule.get("for", "5m"),
                "annotations": rule.get("annotations", {}),
                "labels": rule.get("labels", {}),
                "noDataState": rule.get("noDataState", "NoData"),
                "execErrState": rule.get("execErrState", "Error"),
                "data": rule.get("data", []),
            }
            groups[key]["rules"].append(r_data)
            total_ar += 1

        all_groups.extend(groups.values())

    ctx.client.current_org_id = None

    if total_ar > 0:
        output_file = alerting_dir / "alert_rules.yaml"
        with open(output_file, "w") as f:
            f.write(f"# Imported from {ctx.grafana_url} on {datetime.now().isoformat()}\n\n")
            f.write(yaml_dump({"groups": all_groups}))
        print(f"  {Colors.GREEN}✓{Colors.NC} {total_ar} alert rule(s) across {len(ctx.org_ids)} org(s)")
        ctx.imported_count += 1

    # Notification Policies
    all_policies: list[dict[str, Any]] = []
    total_np = 0

    for org_id in ctx.org_ids:
        ctx.client.current_org_id = org_id
        org_name = ctx.org_map[org_id]

        policy = ctx.client.get("/api/v1/provisioning/policies")
        if not policy or not policy.get("receiver"):
            continue

        policy_entry = _process_notification_policy(policy, org_name)
        all_policies.append(policy_entry)
        total_np += 1

    ctx.client.current_org_id = None

    if total_np > 0:
        output_file = alerting_dir / "notification_policies.yaml"
        with open(output_file, "w") as f:
            f.write(f"# Imported from {ctx.grafana_url} on {datetime.now().isoformat()}\n")
            f.write("#\n")
            f.write("# Notification Policies define how alerts are routed to contact points.\n")
            f.write("# Format follows Grafana's provisioning API structure.\n\n")
            f.write(yaml_dump({"policies": all_policies}))
        print(f"  {Colors.GREEN}✓{Colors.NC} {total_np} notification policy tree(s) across {len(ctx.org_ids)} org(s)")
        ctx.imported_count += 1
    else:
        print(f"  {Colors.DIM}  No notification policies found{Colors.NC}")


def _process_notification_policy(policy: dict[str, Any], org_name: str) -> dict[str, Any]:
    """Process a notification policy into YAML format."""
    entry: dict[str, Any] = {
        "org": org_name,
        "receiver": policy.get("receiver", "grafana-default-email"),
    }

    if policy.get("group_by"):
        entry["group_by"] = policy["group_by"]
    if policy.get("group_wait"):
        entry["group_wait"] = policy["group_wait"]
    if policy.get("group_interval"):
        entry["group_interval"] = policy["group_interval"]
    if policy.get("repeat_interval"):
        entry["repeat_interval"] = policy["repeat_interval"]
    if policy.get("mute_time_intervals"):
        entry["mute_timings"] = policy["mute_time_intervals"]

    if policy.get("routes"):
        entry["routes"] = [_process_route(r) for r in policy["routes"]]

    return entry


def _process_route(route: dict[str, Any]) -> dict[str, Any]:
    """Process a notification policy route recursively."""
    entry: dict[str, Any] = {"receiver": route.get("receiver")}

    if route.get("group_by"):
        entry["group_by"] = route["group_by"]
    if route.get("object_matchers"):
        entry["object_matchers"] = route["object_matchers"]
    if route.get("continue") is not None:
        entry["continue"] = route["continue"]
    if route.get("group_wait"):
        entry["group_wait"] = route["group_wait"]
    if route.get("group_interval"):
        entry["group_interval"] = route["group_interval"]
    if route.get("repeat_interval"):
        entry["repeat_interval"] = route["repeat_interval"]
    if route.get("mute_time_intervals"):
        entry["mute_timings"] = route["mute_time_intervals"]

    if route.get("routes"):
        entry["routes"] = [_process_route(r) for r in route["routes"]]

    return entry


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

        search_results = ctx.client.get("/api/search?type=dash-db&limit=5000") or []
        if not search_results:
            continue

        for dash in search_results:
            uid = dash.get("uid", "")
            folder_uid = dash.get("folderUid", "general") or "general"
            title = dash.get("title", "unknown")

            slug_folder_uid = ctx.folder_uid_map.get(folder_uid, folder_uid)
            safe_title = safe_filename(title)

            folder_path = dash_dir / org_name / slug_folder_uid
            folder_path.mkdir(parents=True, exist_ok=True)

            dash_data = ctx.client.get(f"/api/dashboards/uid/{uid}")
            if dash_data:
                dashboard = dash_data.get("dashboard", {})
                dashboard.pop("id", None)
                dashboard.pop("version", None)

                output_file = folder_path / f"{safe_title}.json"
                with open(output_file, "w") as f:
                    json.dump(dashboard, f, indent=2)

                print(f"  {Colors.GREEN}✓{Colors.NC} {org_name}/{slug_folder_uid}/{safe_title}.json")

    ctx.client.current_org_id = None
    print(f"  {Colors.GREEN}✓{Colors.NC} Exported dashboards to envs/{ctx.env_name}/dashboards/")
    ctx.imported_count += 1


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
        f.write("# Client secret is stored in Vault — see vault-setup.\n\n")

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

    # Allowed groups
    ag = s.get("allowedGroups", "")
    if ag:
        config["allowed_groups"] = parse_json_str(ag, ",")

    # Org mapping → groups format
    org_mapping_str = s.get("orgMapping", "")
    if org_mapping_str:
        config["groups"] = _process_org_mapping(org_mapping_str, org_map)

    # Teams
    if s.get("teamsUrl"):
        config["teams_url"] = s["teamsUrl"]
    if s.get("teamIdsAttributePath"):
        config["team_ids_attribute_path"] = s["teamIdsAttributePath"]
    if s.get("signoutRedirectUrl"):
        config["signout_redirect_url"] = s["signoutRedirectUrl"]

    return config


def _process_org_mapping(org_mapping_str: str, org_map: dict[int, str]) -> list[dict[str, Any]]:
    """Process org_mapping string into groups format."""
    # Parse mappings (may be JSON array string or newline-separated)
    if org_mapping_str.startswith("["):
        try:
            mappings = [m.strip() for m in json.loads(org_mapping_str) if m.strip()]
        except (json.JSONDecodeError, TypeError):
            mappings = [m.strip() for m in org_mapping_str.strip().replace("\\n", "\n").split("\n") if m.strip()]
    else:
        mappings = [m.strip() for m in org_mapping_str.strip().replace("\\n", "\n").split("\n") if m.strip()]

    # Build org_id -> org_name lookup (string keys)
    org_name_lookup = {str(k): v for k, v in org_map.items()}
    all_org_ids = set(org_name_lookup.keys())

    groups: dict[str, list[dict[str, Any]]] = {}
    group_order: list[str] = []

    for m in mappings:
        parts = m.split(":")
        if len(parts) >= 3:
            group_name = parts[0]
            org_id = parts[1]
            role = parts[2]
        elif len(parts) == 2 and parts[1].startswith("*"):
            # Handle malformed entry like "group:*Role" (missing colon after *)
            group_name = parts[0]
            org_id = "*"
            role = parts[1][1:]  # Remove the leading *
            print(f'  {Colors.YELLOW}⚠{Colors.NC} Fixed malformed org_mapping: "{m}" → "{group_name}:*:{role}"', file=sys.stderr)
        else:
            print(f'  {Colors.YELLOW}⚠{Colors.NC} Skipping malformed org_mapping entry: "{m}"', file=sys.stderr)
            continue

        if group_name not in groups:
            groups[group_name] = []
            group_order.append(group_name)

        entry: dict[str, Any] = {"role": role}
        if org_id == "*":
            entry["org"] = "*"
        else:
            entry["org"] = org_name_lookup.get(org_id, org_id)
            entry["_org_id"] = org_id

        groups[group_name].append(entry)

    # Collapse: if a group maps to ALL orgs with the same role, use org: "*"
    for group_name in group_order:
        mappings_list = groups[group_name]
        if any(m["org"] == "*" for m in mappings_list):
            continue

        role_counts: dict[str, list[dict[str, Any]]] = {}
        for m in mappings_list:
            role_counts.setdefault(m["role"], []).append(m)

        for role, role_mappings in role_counts.items():
            covered_ids = {m["_org_id"] for m in role_mappings if "_org_id" in m}
            if len(all_org_ids) > 1 and covered_ids >= all_org_ids:
                remaining = [m for m in mappings_list if m["role"] != role]
                remaining.insert(0, {"org": "*", "role": role})
                groups[group_name] = remaining
                break

    # Build final output
    result: list[dict[str, Any]] = []
    for group_name in group_order:
        group_entry: dict[str, Any] = {"name": group_name}
        if group_name == "*":
            group_entry["wildcard_group"] = True
        group_entry["org_mappings"] = [
            {"org": m["org"], "role": m["role"]} for m in groups[group_name]
        ]
        result.append(group_entry)

    return result


def generate_tfvars(ctx: ImportContext) -> None:
    """Generate terraform.tfvars file if it doesn't exist."""
    tfvars_file = ctx.config_dir / "terraform.tfvars"

    if tfvars_file.exists():
        print(f"  {Colors.DIM}  envs/{ctx.env_name}/terraform.tfvars already exists (skipped){Colors.NC}")
        return

    content = f"""# =============================================================================
# {ctx.env_name.upper()} ENVIRONMENT - Terraform Variables
# =============================================================================
# Auto-generated by import_from_grafana.py on {datetime.now().isoformat()}
#
# Usage:
#   make plan  ENV={ctx.env_name}
#   make apply ENV={ctx.env_name}
# =============================================================================

# The URL of your Grafana instance
grafana_url = "{ctx.grafana_url}"

# Environment name — must match a directory under envs/
environment = "{ctx.env_name}"

# Vault Configuration (HashiCorp Vault for secrets management)
vault_address = "http://localhost:8200"
vault_mount   = "grafana"
# vault_token — set via VAULT_TOKEN env variable for security:
#   export VAULT_TOKEN="your-vault-token"

# Keycloak Configuration (optional — only if you enable SSO via Keycloak)
# keycloak_url = "https://keycloak.example.com"
"""

    with open(tfvars_file, "w") as f:
        f.write(content)

    print(f"  {Colors.GREEN}✓{Colors.NC} Generated envs/{ctx.env_name}/terraform.tfvars")


def print_summary(ctx: ImportContext) -> None:
    """Print import summary."""
    print("")
    print(f"{Colors.GREEN}╔═══════════════════════════════════════════════════════════════╗{Colors.NC}")
    print(f"{Colors.GREEN}║  Import complete!{Colors.NC}")
    print(f"{Colors.GREEN}╚═══════════════════════════════════════════════════════════════╝{Colors.NC}")
    print("")
    print(f"  Source:      {ctx.grafana_url}")
    print(f"  Target env:  {ctx.env_name}")
    print(f"  Orgs:        {len(ctx.org_ids)} ({' '.join(str(i) for i in ctx.org_ids)})")
    print(f"  Imported:    {ctx.imported_count} resource type(s)")
    print("")
    print("  Generated files:")
    print(f"    envs/{ctx.env_name}/")

    for f in sorted(ctx.config_dir.iterdir()):
        print(f"      {f.name}")

    alerting_dir = ctx.config_dir / "alerting"
    if alerting_dir.exists():
        print(f"    envs/{ctx.env_name}/alerting/")
        for f in sorted(alerting_dir.iterdir()):
            print(f"      {f.name}")

    if ctx.import_dashboards:
        dash_dir = ctx.output_dir / "envs" / ctx.env_name / "dashboards"
        if dash_dir.exists():
            dash_count = len(list(dash_dir.rglob("*.json")))
            print(f"    envs/{ctx.env_name}/dashboards/ ({dash_count} dashboards)")
            for org_id in ctx.org_ids:
                org_name = ctx.org_map[org_id]
                org_dash_dir = dash_dir / org_name
                if org_dash_dir.exists():
                    org_dash_count = len(list(org_dash_dir.rglob("*.json")))
                    print(f"      {org_name}: {org_dash_count} dashboards")

    print("")
    print(f"  {Colors.YELLOW}⚠  Review and adjust the generated YAML files before applying!{Colors.NC}")
    print("  Some values (SSO, secrets, Keycloak) need manual configuration.")
    print("")
    print("  Next steps:")
    print(f"    1. Review envs/{ctx.env_name}/*.yaml")
    print(f"    2. Review envs/{ctx.env_name}/terraform.tfvars")
    print(f"    3. Set up Vault secrets: make vault-setup ENV={ctx.env_name}")
    print(f"    4. Run: make init ENV={ctx.env_name} && make plan ENV={ctx.env_name}")
    print("")


# =============================================================================
# Main Entry Point
# =============================================================================
def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Import Grafana configuration into YAML files for Terraform.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python scripts/import_from_grafana.py prod --grafana-url=http://localhost:3000 --auth=admin:admin
    python scripts/import_from_grafana.py dev --grafana-url=https://grafana.example.com --auth=glsa_xxx
        """,
    )
    parser.add_argument("env_name", help="Target environment name")
    parser.add_argument("--grafana-url", required=True, help="Grafana instance URL")
    parser.add_argument("--auth", required=True, help="API token or user:password")
    parser.add_argument("--no-dashboards", action="store_true", help="Skip dashboard import")
    parser.add_argument("--output-dir", help="Output directory (default: project root)")

    args = parser.parse_args()

    # Determine paths
    script_dir = Path(__file__).resolve().parent
    project_root = script_dir.parent
    output_dir = Path(args.output_dir) if args.output_dir else project_root
    config_dir = output_dir / "envs" / args.env_name

    # Create directories
    config_dir.mkdir(parents=True, exist_ok=True)
    (config_dir / "alerting").mkdir(parents=True, exist_ok=True)

    # Create client and context
    grafana_url = args.grafana_url.rstrip("/")
    client = GrafanaClient(url=grafana_url, auth=args.auth)

    ctx = ImportContext(
        env_name=args.env_name,
        grafana_url=grafana_url,
        client=client,
        output_dir=output_dir,
        config_dir=config_dir,
        import_dashboards=not args.no_dashboards,
    )

    # Print header
    print(f"{Colors.BOLD}{Colors.CYAN}")
    print("╔═══════════════════════════════════════════════════════════════╗")
    print(f"║          Importing from Grafana → {args.env_name}")
    print("╚═══════════════════════════════════════════════════════════════╝")
    print(f"{Colors.NC}")

    # Test connection
    health = client.health()
    if health and health.get("database") == "ok":
        version = health.get("version", "unknown")
        print(f"  {Colors.GREEN}✓{Colors.NC} Connected to Grafana {version} at {grafana_url}")
    else:
        print(f"  {Colors.RED}✗ Cannot connect to Grafana at {grafana_url}{Colors.NC}")
        return 1
    print("")

    # Run imports
    import_organizations(ctx)
    import_datasources(ctx)
    import_folders(ctx)
    import_teams(ctx)
    import_service_accounts(ctx)
    import_alerting(ctx)
    import_dashboards(ctx)
    import_sso(ctx)
    generate_tfvars(ctx)

    # Print summary
    print_summary(ctx)

    return 0


if __name__ == "__main__":
    sys.exit(main())
