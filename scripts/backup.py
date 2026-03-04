#!/usr/bin/env python3
"""
Backup — Snapshot current Grafana state via API before destructive operations.

Exports dashboards, datasources, and alert config from Grafana to a
timestamped backup directory. Useful as a safety net before `terraform apply`.

Usage:
    python scripts/backup.py <env-name>
    make backup ENV=prod
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

import requests


class Colors:
    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    BLUE = "\033[0;34m"
    CYAN = "\033[0;36m"
    DIM = "\033[2m"
    BOLD = "\033[1m"
    NC = "\033[0m"


def make_session(auth: str) -> requests.Session:
    session = requests.Session()
    if ":" in auth:
        user, password = auth.split(":", 1)
        session.auth = (user, password)
    else:
        session.headers["Authorization"] = f"Bearer {auth}"
    return session


def grafana_get(session: requests.Session, grafana_url: str, endpoint: str) -> object:
    try:
        resp = session.get(f"{grafana_url}{endpoint}", timeout=15)
        resp.raise_for_status()
        return resp.json()
    except Exception:
        return None


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Snapshot current Grafana state via API"
    )
    parser.add_argument("env", help="Environment name")
    args = parser.parse_args()

    env: str = args.env
    project_root = Path(__file__).resolve().parent.parent

    tfvars_file = project_root / "envs" / env / "terraform.tfvars"
    if not tfvars_file.is_file():
        print(f"{Colors.RED}Error: envs/{env}/terraform.tfvars not found{Colors.NC}")
        sys.exit(1)

    content = tfvars_file.read_text()
    match = re.search(r'^grafana_url\s*=\s*"?([^"\n]+)"?', content, re.MULTILINE)
    if not match:
        print(f"{Colors.RED}Error: grafana_url not found in terraform.tfvars{Colors.NC}")
        sys.exit(1)
    grafana_url = match.group(1).strip().strip('"')

    auth = os.environ.get("GRAFANA_AUTH", "admin:admin")

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_dir = project_root / "backups" / env / timestamp
    backup_dir.mkdir(parents=True, exist_ok=True)

    print(f"{Colors.BOLD}{Colors.CYAN}")
    print("╔═══════════════════════════════════════════════════════════════╗")
    print(f"║          Backup: {env} → backups/{env}/{timestamp}")
    print("╚═══════════════════════════════════════════════════════════════╝")
    print(f"{Colors.NC}")

    session = make_session(auth)

    # Test connection
    health = grafana_get(session, grafana_url, "/api/health")
    if not health or not (health.get("database") == "ok" or "ok" in str(health)):
        print(f"{Colors.RED}Cannot connect to Grafana at {grafana_url}{Colors.NC}")
        print("  Set GRAFANA_AUTH env var (e.g., export GRAFANA_AUTH=admin:admin)")
        sys.exit(1)
    print(f"  {Colors.GREEN}✓{Colors.NC} Connected to {grafana_url}")
    print()

    total = 0

    # 1. Datasources
    print(f"{Colors.BLUE}[1/5]{Colors.NC} Backing up datasources...")
    ds_data = grafana_get(session, grafana_url, "/api/datasources") or []
    (backup_dir / "datasources.json").write_text(json.dumps(ds_data, indent=2))
    ds_count = len(ds_data) if isinstance(ds_data, list) else 0
    print(f"  {Colors.GREEN}✓{Colors.NC} {ds_count} datasource(s)")
    total += ds_count

    # 2. Folders
    print(f"{Colors.BLUE}[2/5]{Colors.NC} Backing up folders...")
    folders_data = grafana_get(session, grafana_url, "/api/folders?limit=1000") or []
    (backup_dir / "folders.json").write_text(json.dumps(folders_data, indent=2))
    folder_count = len(folders_data) if isinstance(folders_data, list) else 0
    print(f"  {Colors.GREEN}✓{Colors.NC} {folder_count} folder(s)")
    total += folder_count

    # 3. Dashboards
    print(f"{Colors.BLUE}[3/5]{Colors.NC} Backing up dashboards...")
    dash_dir = backup_dir / "dashboards"
    dash_dir.mkdir(exist_ok=True)
    search_data = grafana_get(session, grafana_url, "/api/search?type=dash-db&limit=5000") or []
    for item in search_data:
        uid = item.get("uid", "")
        if not uid:
            continue
        dash = grafana_get(session, grafana_url, f"/api/dashboards/uid/{uid}")
        if dash:
            title = dash.get("dashboard", {}).get("title", uid)
            safe_title = re.sub(r"[^a-zA-Z0-9 _\-]", "", title)
            (dash_dir / f"{safe_title}.json").write_text(json.dumps(dash, indent=2))
    dash_files = len(list(dash_dir.glob("*.json")))
    print(f"  {Colors.GREEN}✓{Colors.NC} {dash_files} dashboard(s)")
    total += dash_files

    # 4. Alert rules
    print(f"{Colors.BLUE}[4/5]{Colors.NC} Backing up alert configuration...")
    alert_rules = grafana_get(session, grafana_url, "/api/v1/provisioning/alert-rules") or []
    (backup_dir / "alert_rules.json").write_text(json.dumps(alert_rules, indent=2))
    contact_points = grafana_get(session, grafana_url, "/api/v1/provisioning/contact-points") or []
    (backup_dir / "contact_points.json").write_text(json.dumps(contact_points, indent=2))
    policies = grafana_get(session, grafana_url, "/api/v1/provisioning/policies") or {}
    (backup_dir / "notification_policies.json").write_text(json.dumps(policies, indent=2))
    print(f"  {Colors.GREEN}✓{Colors.NC} Alert rules, contact points, notification policies")
    total += 3

    # 5. Organizations & Teams
    print(f"{Colors.BLUE}[5/5]{Colors.NC} Backing up organizations & teams...")
    orgs = grafana_get(session, grafana_url, "/api/orgs") or []
    (backup_dir / "organizations.json").write_text(json.dumps(orgs, indent=2))
    teams = grafana_get(session, grafana_url, "/api/teams/search?perpage=1000") or {"teams": []}
    (backup_dir / "teams.json").write_text(json.dumps(teams, indent=2))
    print(f"  {Colors.GREEN}✓{Colors.NC} Organizations & teams")
    total += 2

    # Summary
    backup_size = "unknown"
    try:
        total_bytes = sum(f.stat().st_size for f in backup_dir.rglob("*") if f.is_file())
        for unit in ["B", "KB", "MB", "GB"]:
            if total_bytes < 1024:
                backup_size = f"{total_bytes:.1f}{unit}"
                break
            total_bytes /= 1024
    except Exception:
        pass

    print()
    print(f"{Colors.GREEN}╔═══════════════════════════════════════════════════════════════╗{Colors.NC}")
    print(f"{Colors.GREEN}║  Backup complete!{Colors.NC}")
    print(f"{Colors.GREEN}╚═══════════════════════════════════════════════════════════════╝{Colors.NC}")
    print()
    print(f"  Location:  backups/{env}/{timestamp}/")
    print(f"  Size:      {backup_size}")
    print(f"  Items:     {total} resource(s)")
    print()
    print("  Files:")
    for f in sorted(backup_dir.iterdir()):
        print(f"    {f.name}")
    print()
    print("  To restore, use the Grafana API or re-import:")
    print(
        f"    python3 scripts/import_from_grafana.py {env}-restored"
        f" --grafana-url={grafana_url} --auth=$AUTH"
    )
    print()


if __name__ == "__main__":
    main()
