"""Import alerting configuration from Grafana (contact points, rules, policies)."""

from __future__ import annotations

import sys
from datetime import datetime
from typing import Any

from .common import Colors, ImportContext, yaml_dump


# ---------------------------------------------------------------------------
# Contact-point secret detection
# ---------------------------------------------------------------------------
_CP_SECRET_FIELDS: dict[str, list[str]] = {
    "webhook":      ["url", "password", "tlsClientCert", "tlsClientKey", "authorizationCredentials"],
    "slack":        ["token", "url", "recipient"],
    "pagerduty":    ["integrationKey", "serviceKey"],
    "opsgenie":     ["apiKey", "apiUrl"],
    "email":        [],
    "telegram":     ["botToken"],
    "discord":      ["url"],
    "teams":        ["url"],
    "googlechat":   ["url"],
    "victorops":    ["apiKey", "url"],
    "pushover":     ["apiToken", "userKey"],
    "sns":          ["accessKey", "secretKey"],
    "threema":      ["apiSecret"],
    "webex":        ["botToken", "roomId"],
    "line":         ["token"],
    "kafka":        ["password"],
    "oncall":       ["url", "httpPassword", "authorizationCredentials"],
    "alertmanager": ["basicAuthPassword"],
    "sensugo":      ["apiKey"],
}


def _vault_sentinel(vault_path: str, key: str) -> str:
    """Build a VAULT_SECRET_REQUIRED sentinel value.

    Format: VAULT_SECRET_REQUIRED:<path-relative-to-mount>:<key>
    The vault_path should NOT include the mount prefix (e.g. 'grafana/').
    """
    return f"VAULT_SECRET_REQUIRED:{vault_path}:{key}"


def _redact_contact_point_secrets(
    recv_type: str,
    settings: dict,
    vault_path: str,
) -> tuple[dict, list[str]]:
    """Scrub known-sensitive fields and replace with vault sentinels.

    Grafana returns '' for unset secrets, '[REDACTED]' for set ones.
    Both are replaced with VAULT_SECRET_REQUIRED sentinels.
    """
    secret_fields = _CP_SECRET_FIELDS.get(recv_type, [])
    cleaned = dict(settings)
    found: list[str] = []

    _REDACTED_VALUES = {"", "[REDACTED]"}

    def _is_redacted(v: Any) -> bool:
        if v in _REDACTED_VALUES or v is None:
            return True
        if isinstance(v, str) and v.startswith("changeme_"):
            return True
        return False

    for field in secret_fields:
        val = cleaned.get(field)
        if _is_redacted(val):
            cleaned[field] = _vault_sentinel(vault_path, field)
            found.append(field)

    for k, v in list(cleaned.items()):
        if k not in secret_fields and isinstance(v, str) and v in _REDACTED_VALUES and not k.startswith("#"):
            cleaned[k] = _vault_sentinel(vault_path, k)
            found.append(k)

    return cleaned, found


def _process_notification_policy(policy: dict[str, Any], org_name: str, org_id: int) -> dict[str, Any]:
    """Process a notification policy into YAML format."""
    entry: dict[str, Any] = {
        "org": org_name,
        "orgId": org_id,
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
    if policy.get("matchers"):
        entry["matchers"] = policy["matchers"]
    if policy.get("object_matchers"):
        entry["object_matchers"] = policy["object_matchers"]
    if policy.get("mute_time_intervals"):
        entry["mute_time_intervals"] = policy["mute_time_intervals"]
    if policy.get("active_time_intervals"):
        entry["active_time_intervals"] = policy["active_time_intervals"]

    if policy.get("routes"):
        entry["routes"] = [_process_route(r) for r in policy["routes"]]

    return entry


def _process_route(route: dict[str, Any]) -> dict[str, Any]:
    """Process a notification policy route recursively."""
    entry: dict[str, Any] = {}

    if route.get("receiver"):
        entry["receiver"] = route["receiver"]
    if route.get("group_by"):
        entry["group_by"] = route["group_by"]
    if route.get("matchers"):
        entry["matchers"] = route["matchers"]
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
        entry["mute_time_intervals"] = route["mute_time_intervals"]
    if route.get("active_time_intervals"):
        entry["active_time_intervals"] = route["active_time_intervals"]

    if route.get("routes"):
        entry["routes"] = [_process_route(r) for r in route["routes"]]

    return entry


def import_alerting(ctx: ImportContext) -> None:
    """Import alerting configuration (contact points, rules, policies)."""
    print(f"{Colors.BLUE}[6/8]{Colors.NC} Importing alerting configuration...")

    alerting_dir = ctx.config_dir / "alerting"
    alerting_dir.mkdir(parents=True, exist_ok=True)

    # ── Contact Points ──────────────────────────────────────────────────────
    all_contact_points: list[dict[str, Any]] = []
    total_cp = 0

    for org_id in ctx.org_ids:
        ctx.client.current_org_id = org_id
        org_name = ctx.org_map[org_id]

        contact_points = ctx.client.get("/api/v1/provisioning/contact-points") or []

        am_config = ctx.client.get("/api/alertmanager/grafana/config/api/v1/alerts") or {}
        am_receivers = am_config.get("alertmanager_config", {}).get("receivers", [])
        provisioned_names = {cp["name"] for cp in contact_points}
        for am_recv in am_receivers:
            if am_recv["name"] not in provisioned_names:
                contact_points.append({
                    "name": am_recv["name"],
                    "type": "__empty__",
                    "settings": {},
                    "_no_integrations": True,
                })

        grouped: dict[str, dict[str, Any]] = {}
        for cp in contact_points:
            name = cp["name"]
            if cp.get("_no_integrations"):
                if name not in grouped:
                    grouped[name] = {"name": name, "org": org_name, "orgId": org_id, "receivers": []}
                continue
            if name not in grouped:
                grouped[name] = {"name": name, "org": org_name, "orgId": org_id, "receivers": []}

            recv: dict[str, Any] = {"type": cp["type"]}
            settings = cp.get("settings", {})
            secrets_found: list[str] = []
            if settings:
                # Build vault path relative to mount: <env>/<org-slug>/alerting/contact-points/<cp-slug>
                import re
                org_slug = re.sub(r'[^a-zA-Z0-9_-]+', '-', org_name).strip('-').lower()
                cp_slug = re.sub(r'[^a-zA-Z0-9_-]+', '-', name).strip('-').lower()
                vault_path = f"{ctx.env_name}/{org_slug}/alerting/contact-points/{cp_slug}"
                cleaned, secrets_found = _redact_contact_point_secrets(
                    cp["type"], settings, vault_path=vault_path
                )
                recv["settings"] = cleaned

            dis_resolve = cp.get("disableResolveMessage")
            if dis_resolve is not None:
                recv["disableResolveMessage"] = dis_resolve
            grouped[name]["receivers"].append(recv)
            total_cp += 1

        if not ctx.skip_tf_import:
            for cp_entry in grouped.values():
                if cp_entry.get("receivers"):
                    tf_key = f"{org_name}:{cp_entry['name']}"
                    ctx.tf_imports.append((
                        f'module.alerting.grafana_contact_point.contact_points["{tf_key}"]',
                        f"{org_id}:{cp_entry['name']}",
                    ))

        org_dir = alerting_dir / org_name
        org_dir.mkdir(parents=True, exist_ok=True)
        output_file = org_dir / "contact_points.yaml"
        with open(output_file, "w") as f:
            f.write(f"# Imported from {ctx.grafana_url} on {datetime.now().isoformat()}\n\n")
            f.write(yaml_dump({"contactPoints": list(grouped.values()) if grouped else []}))

    ctx.client.current_org_id = None

    if total_cp > 0:
        print(f"  {Colors.GREEN}✓{Colors.NC} {total_cp} contact point(s) → envs/{ctx.env_name}/alerting/<org>/contact_points.yaml")
    else:
        print(f"  {Colors.DIM}  0 contact points (empty files created per org){Colors.NC}")
    ctx.imported_count += 1

    # ── Alert Rules ─────────────────────────────────────────────────────────
    all_groups: list[dict[str, Any]] = []
    total_ar = 0

    for org_id in ctx.org_ids:
        ctx.client.current_org_id = org_id
        org_name = ctx.org_map[org_id]

        rules = ctx.client.get("/api/v1/provisioning/alert-rules") or []

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
                    "orgId": org_id,
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

        if not ctx.skip_tf_import:
            for group_entry in groups.values():
                tf_key = f"{org_name}:{group_entry['folder']}-{group_entry['name']}"
                original_folder_uid = group_entry['folder']
                for old_uid, slug in ctx.folder_uid_map.items():
                    if slug == group_entry['folder']:
                        original_folder_uid = old_uid
                        break
                ctx.tf_imports.append((
                    f'module.alerting.grafana_rule_group.rule_groups["{tf_key}"]',
                    f"{org_id}:{original_folder_uid}:{group_entry['name']}",
                ))

        org_dir = alerting_dir / org_name
        org_dir.mkdir(parents=True, exist_ok=True)
        output_file = org_dir / "alert_rules.yaml"
        with open(output_file, "w") as f:
            f.write(f"# Imported from {ctx.grafana_url} on {datetime.now().isoformat()}\n\n")
            f.write("apiVersion: 1\n")
            f.write(yaml_dump({"groups": list(groups.values()) if groups else []}))

    ctx.client.current_org_id = None

    if total_ar > 0:
        print(f"  {Colors.GREEN}✓{Colors.NC} {total_ar} alert rule(s) → envs/{ctx.env_name}/alerting/<org>/alert_rules.yaml")
    else:
        print(f"  {Colors.DIM}  0 alert rules (empty files created per org){Colors.NC}")
    ctx.imported_count += 1

    # ── Notification Policies ───────────────────────────────────────────────
    all_policies: list[dict[str, Any]] = []
    total_np = 0

    for org_id in ctx.org_ids:
        ctx.client.current_org_id = org_id
        org_name = ctx.org_map[org_id]

        policy = ctx.client.get("/api/v1/provisioning/policies")
        policy_entry = None
        if policy and policy.get("receiver"):
            policy_entry = _process_notification_policy(policy, org_name, org_id)

        if not ctx.skip_tf_import and policy_entry:
            ctx.tf_imports.append((
                f'module.alerting.grafana_notification_policy.policy["{org_name}"]',
                f"{org_id}:policy",
            ))

        org_dir = alerting_dir / org_name
        org_dir.mkdir(parents=True, exist_ok=True)
        output_file = org_dir / "notification_policies.yaml"
        with open(output_file, "w") as f:
            f.write(f"# Imported from {ctx.grafana_url} on {datetime.now().isoformat()}\n")
            f.write("#\n")
            f.write("# Notification Policies define how alerts are routed to contact points.\n")
            f.write("# Format follows Grafana's provisioning API structure.\n\n")
            if policy_entry:
                f.write(yaml_dump({"policies": [policy_entry]}))
                total_np += 1
            else:
                f.write(yaml_dump({"policies": []}))

    ctx.client.current_org_id = None

    if total_np > 0:
        print(f"  {Colors.GREEN}✓{Colors.NC} {total_np} notification policy(ies) → envs/{ctx.env_name}/alerting/<org>/notification_policies.yaml")
    else:
        print(f"  {Colors.DIM}  0 notification policies (empty files created per org){Colors.NC}")
    ctx.imported_count += 1
