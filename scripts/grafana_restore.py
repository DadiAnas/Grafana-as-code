#!/usr/bin/env python3
"""
Grafana State Recovery Script
-------------------------------
Reads terraform.tfstate and restores all resources to Grafana via HTTP API.

Supported resource types:
  - grafana_organization
  - grafana_folder
  - grafana_folder_permission
  - grafana_data_source
  - grafana_dashboard
  - grafana_team
  - grafana_service_account
  - grafana_contact_point
  - grafana_notification_policy
  - grafana_sso_settings

Usage:
  pip install requests
  python grafana_restore.py \
    --state terraform.tfstate \
    --url https://your-grafana.example.com \
    --user admin \
    --password yourpassword

  Add --dry-run to preview without making any changes.
"""

import argparse
import json
import requests
from requests.auth import HTTPBasicAuth

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN  = "\033[92m"
YELLOW = "\033[93m"
RED    = "\033[91m"
CYAN   = "\033[96m"
RESET  = "\033[0m"

def ok(msg):   print(f"{GREEN}  [OK]{RESET}   {msg}")
def warn(msg): print(f"{YELLOW}  [WARN]{RESET} {msg}")
def err(msg):  print(f"{RED}  [ERR]{RESET}  {msg}")

# ── HTTP helpers ──────────────────────────────────────────────────────────────
def call(method, base_url, path, auth, payload=None, dry_run=False):
    url = base_url.rstrip("/") + path
    if dry_run:
        print(f"  DRY-RUN {method.upper()} {url}")
        if payload:
            print(json.dumps(payload, indent=4))
        return {"id": "dry-run", "uid": "dry-run", "message": "dry-run"}
    resp = getattr(requests, method)(url, json=payload, auth=auth, timeout=30)
    if resp.status_code not in (200, 201):
        raise RuntimeError(f"HTTP {resp.status_code} → {resp.text[:300]}")
    return resp.json()

def already_exists(e):
    return "already exists" in str(e).lower() or "conflict" in str(e).lower()

# ── Parse tfstate ─────────────────────────────────────────────────────────────
KNOWN_TYPES = [
    "grafana_organization",
    "grafana_folder",
    "grafana_folder_permission",
    "grafana_data_source",
    "grafana_dashboard",
    "grafana_team",
    "grafana_service_account",
    "grafana_contact_point",
    "grafana_notification_policy",
    "grafana_sso_settings",
]

def load_resources(state_path):
    with open(state_path) as f:
        state = json.load(f)

    buckets = {t: [] for t in KNOWN_TYPES}
    buckets["other"] = []

    for resource in state.get("resources", []):
        rtype = resource.get("type", "")
        for instance in resource.get("instances", []):
            attrs = instance.get("attributes", {})
            entry = {"_type": rtype, **attrs}
            if rtype in buckets:
                buckets[rtype].append(entry)
            else:
                buckets["other"].append(entry)

    return buckets

def parse_json_field(value):
    if isinstance(value, str):
        try:
            return json.loads(value)
        except (json.JSONDecodeError, TypeError):
            pass
    return value

# ── Restore functions ─────────────────────────────────────────────────────────

def restore_organizations(items, base_url, auth, dry_run):
    if not items:
        return
    print(f"\n── Organizations ({len(items)}) ──────────────────────────")
    for item in items:
        name = item.get("name", "Unknown Org")
        try:
            result = call("post", base_url, "/api/orgs", auth, {"name": name}, dry_run)
            ok(f"Organization '{name}' → id={result.get('orgId', result.get('id', '?'))}")
        except RuntimeError as e:
            warn(f"Organization '{name}' already exists — skipping") if already_exists(e) else err(f"Organization '{name}': {e}")


def restore_folders(items, base_url, auth, dry_run):
    if not items:
        return
    print(f"\n── Folders ({len(items)}) ────────────────────────────────")
    for item in items:
        title = item.get("title", "Untitled")
        uid   = item.get("uid") or None
        payload = {"title": title}
        if uid:
            payload["uid"] = uid
        try:
            result = call("post", base_url, "/api/folders", auth, payload, dry_run)
            ok(f"Folder '{title}' → uid={result.get('uid', '?')}")
        except RuntimeError as e:
            warn(f"Folder '{title}' already exists — skipping") if already_exists(e) else err(f"Folder '{title}': {e}")


def restore_folder_permissions(items, base_url, auth, dry_run):
    if not items:
        return
    print(f"\n── Folder Permissions ({len(items)}) ─────────────────────")
    for item in items:
        folder_uid  = item.get("folder_uid") or item.get("folder_id") or ""
        permissions = parse_json_field(item.get("permissions", []))
        if not folder_uid:
            warn("Folder permission entry has no folder_uid — skipping")
            continue
        payload = {"items": permissions if isinstance(permissions, list) else []}
        try:
            call("post", base_url, f"/api/folders/{folder_uid}/permissions", auth, payload, dry_run)
            ok(f"Permissions set for folder uid={folder_uid}")
        except RuntimeError as e:
            err(f"Folder permissions uid={folder_uid}: {e}")


def restore_datasources(items, base_url, auth, dry_run):
    if not items:
        return
    print(f"\n── Datasources ({len(items)}) ────────────────────────────")
    skip_keys = {"id", "_type"}
    for item in items:
        name = item.get("name", "Unknown")
        payload = {k: v for k, v in item.items() if k not in skip_keys and v is not None}
        for field in ("json_data", "json_data_encoded", "secure_json_data", "json_data_with_secure_fields_omitted"):
            if field in payload:
                payload[field] = parse_json_field(payload[field])
        try:
            call("post", base_url, "/api/datasources", auth, payload, dry_run)
            ok(f"Datasource '{name}' (type={item.get('type', '?')})")
        except RuntimeError as e:
            warn(f"Datasource '{name}' already exists — skipping") if already_exists(e) else err(f"Datasource '{name}': {e}")


def restore_dashboards(items, base_url, auth, dry_run):
    if not items:
        return
    print(f"\n── Dashboards ({len(items)}) ──────────────────────────────")
    for item in items:
        config = parse_json_field(item.get("config_json") or item.get("dashboard") or {})
        title  = config.get("title") or item.get("title", "Unknown Dashboard")
        folder_uid = item.get("folder") or item.get("folder_uid") or ""
        config.pop("id", None)
        config.pop("version", None)
        payload = {
            "dashboard": config,
            "folderUid": folder_uid,
            "overwrite": True,
            "message":   "Restored from tfstate",
        }
        try:
            result = call("post", base_url, "/api/dashboards/db", auth, payload, dry_run)
            ok(f"Dashboard '{title}' → uid={result.get('uid', '?')}")
        except RuntimeError as e:
            err(f"Dashboard '{title}': {e}")


def restore_teams(items, base_url, auth, dry_run):
    if not items:
        return
    print(f"\n── Teams ({len(items)}) ──────────────────────────────────")
    for item in items:
        name  = item.get("name", "Unknown Team")
        email = item.get("email", "")
        try:
            result = call("post", base_url, "/api/teams", auth, {"name": name, "email": email}, dry_run)
            ok(f"Team '{name}' → id={result.get('teamId', result.get('id', '?'))}")
        except RuntimeError as e:
            warn(f"Team '{name}' already exists — skipping") if already_exists(e) else err(f"Team '{name}': {e}")


def restore_service_accounts(items, base_url, auth, dry_run):
    if not items:
        return
    print(f"\n── Service Accounts ({len(items)}) ───────────────────────")
    for item in items:
        name = item.get("name", "Unknown SA")
        role = item.get("role", "Viewer")
        payload = {"name": name, "role": role, "isDisabled": item.get("is_disabled", False)}
        try:
            result = call("post", base_url, "/api/serviceaccounts", auth, payload, dry_run)
            ok(f"Service account '{name}' → id={result.get('id', '?')}")
        except RuntimeError as e:
            warn(f"Service account '{name}' already exists — skipping") if already_exists(e) else err(f"Service account '{name}': {e}")


def restore_contact_points(items, base_url, auth, dry_run):
    if not items:
        return
    print(f"\n── Contact Points ({len(items)}) ─────────────────────────")
    skip_keys = {"id", "_type"}
    for item in items:
        name = item.get("name", "Unknown")
        payload = {k: v for k, v in item.items() if k not in skip_keys and v is not None}
        if "settings" in payload:
            payload["settings"] = parse_json_field(payload["settings"])
        try:
            call("post", base_url, "/api/v1/provisioning/contact-points", auth, payload, dry_run)
            ok(f"Contact point '{name}' (type={item.get('type', '?')})")
        except RuntimeError as e:
            warn(f"Contact point '{name}' already exists — skipping") if already_exists(e) else err(f"Contact point '{name}': {e}")


def restore_notification_policy(items, base_url, auth, dry_run):
    if not items:
        return
    print(f"\n── Notification Policy ───────────────────────────────────")
    if len(items) > 1:
        warn("Multiple notification policy entries found — using the last one")
    item = items[-1]
    skip_keys = {"id", "_type"}
    payload = {k: v for k, v in item.items() if k not in skip_keys and v is not None}
    for field in ("route", "routes", "group_by", "object_matchers", "mute_timings"):
        if field in payload:
            payload[field] = parse_json_field(payload[field])
    try:
        call("put", base_url, "/api/v1/provisioning/policies", auth, payload, dry_run)
        ok("Notification policy tree restored")
    except RuntimeError as e:
        err(f"Notification policy: {e}")


def restore_sso_settings(items, base_url, auth, dry_run):
    if not items:
        return
    print(f"\n── SSO Settings ({len(items)}) ───────────────────────────")
    for item in items:
        provider = item.get("provider_name") or item.get("provider", "unknown")
        settings = parse_json_field(item.get("settings") or item.get("oauth_settings") or {})
        try:
            call("put", base_url, f"/api/v1/sso-settings/{provider}", auth, {"settings": settings}, dry_run)
            ok(f"SSO settings for provider '{provider}'")
        except RuntimeError as e:
            err(f"SSO settings '{provider}': {e}")


def report_other(items):
    if not items:
        return
    types = sorted(set(i.get("_type", "unknown") for i in items))
    print(f"\n── Unhandled resource types ──────────────────────────────")
    for t in types:
        count = sum(1 for i in items if i.get("_type") == t)
        warn(f"{t} ({count} instance(s)) — tell me and I'll add support")


# ── Main ──────────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="Restore Grafana resources from terraform.tfstate")
    parser.add_argument("--state",    required=True,  help="Path to terraform.tfstate")
    parser.add_argument("--url",      required=True,  help="Grafana base URL")
    parser.add_argument("--user",     required=True,  help="Grafana username")
    parser.add_argument("--password", required=True,  help="Grafana password")
    parser.add_argument("--dry-run",  action="store_true", help="Preview only — no API calls made")
    args = parser.parse_args()

    auth = HTTPBasicAuth(args.user, args.password)

    print(f"\n{CYAN}Loading state:{RESET} {args.state}")
    buckets = load_resources(args.state)

    print(f"\n{CYAN}Resources found in state:{RESET}")
    for rtype, items in buckets.items():
        if items:
            print(f"  {rtype}: {len(items)}")

    if args.dry_run:
        print(f"\n{YELLOW}DRY-RUN mode — no changes will be made to Grafana{RESET}")

    # Strict dependency order
    restore_organizations(      buckets["grafana_organization"],        args.url, auth, args.dry_run)
    restore_teams(              buckets["grafana_team"],                 args.url, auth, args.dry_run)
    restore_service_accounts(   buckets["grafana_service_account"],     args.url, auth, args.dry_run)
    restore_folders(            buckets["grafana_folder"],              args.url, auth, args.dry_run)
    restore_folder_permissions( buckets["grafana_folder_permission"],   args.url, auth, args.dry_run)
    restore_datasources(        buckets["grafana_data_source"],         args.url, auth, args.dry_run)
    restore_contact_points(     buckets["grafana_contact_point"],       args.url, auth, args.dry_run)
    restore_notification_policy(buckets["grafana_notification_policy"], args.url, auth, args.dry_run)
    restore_dashboards(         buckets["grafana_dashboard"],           args.url, auth, args.dry_run)
    restore_sso_settings(       buckets["grafana_sso_settings"],        args.url, auth, args.dry_run)
    report_other(               buckets["other"])

    print(f"\n{GREEN}Done.{RESET}\n")

if __name__ == "__main__":
    main()
