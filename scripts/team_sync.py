#!/usr/bin/env python3
"""
Team Sync — One-way sync: Keycloak → Grafana (Keycloak is source of truth).

For every team with external_groups in teams.yaml the script:
  • ADDs Grafana team members that exist in the mapped Keycloak group(s)
  • REMOVEs Grafana team members that are no longer in any mapped group

This replaces the Enterprise-only grafana_team_external_group resource
by using the Grafana team members API + Keycloak admin API.

Usage:
    python scripts/team_sync.py <teams-yaml> \\
        --grafana-url=<url> --grafana-auth=<user:pass> \\
        --keycloak-url=<url> --keycloak-realm=<realm> \\
        --keycloak-user=<user> --keycloak-pass=<pass>

Environment variables (alternative to flags):
    GRAFANA_URL, GRAFANA_AUTH, KEYCLOAK_URL, KEYCLOAK_REALM,
    KEYCLOAK_USER, KEYCLOAK_PASS, DRY_RUN
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Any
from urllib.parse import quote as urlquote

import requests
import yaml


class Colors:
    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    BLUE = "\033[0;34m"
    CYAN = "\033[0;36m"
    DIM = "\033[2m"
    BOLD = "\033[1m"
    NC = "\033[0m"


def make_grafana_session(auth: str) -> requests.Session:
    session = requests.Session()
    if ":" in auth:
        user, password = auth.split(":", 1)
        session.auth = (user, password)
    else:
        session.headers["Authorization"] = f"Bearer {auth}"
    session.headers["Content-Type"] = "application/json"
    return session


def grafana_get(
    session: requests.Session,
    grafana_url: str,
    path: str,
    org_id: int | None = None,
) -> Any:
    headers = {}
    if org_id:
        headers["X-Grafana-Org-Id"] = str(org_id)
    try:
        resp = session.get(
            f"{grafana_url}{path}", headers=headers, timeout=15
        )
        return resp.json() if resp.text.strip() else None
    except Exception:
        return None


def grafana_post(
    session: requests.Session,
    grafana_url: str,
    path: str,
    data: dict,
    org_id: int | None = None,
) -> tuple[int, Any]:
    headers = {}
    if org_id:
        headers["X-Grafana-Org-Id"] = str(org_id)
    try:
        resp = session.post(
            f"{grafana_url}{path}", json=data, headers=headers, timeout=15
        )
        body = resp.json() if resp.text.strip() else None
        return resp.status_code, body
    except Exception:
        return 0, None


def grafana_delete(
    session: requests.Session,
    grafana_url: str,
    path: str,
    org_id: int | None = None,
) -> tuple[int, Any]:
    headers = {}
    if org_id:
        headers["X-Grafana-Org-Id"] = str(org_id)
    try:
        resp = session.delete(
            f"{grafana_url}{path}", headers=headers, timeout=15
        )
        body = resp.json() if resp.text.strip() else None
        return resp.status_code, body
    except Exception:
        return 0, None


def get_keycloak_token(
    kc_url: str, kc_user: str, kc_pass: str, verify_ssl: bool = True
) -> str:
    resp = requests.post(
        f"{kc_url}/realms/master/protocol/openid-connect/token",
        data={
            "client_id": "admin-cli",
            "username": kc_user,
            "password": kc_pass,
            "grant_type": "password",
        },
        timeout=15,
        verify=verify_ssl,
    )
    resp.raise_for_status()
    return resp.json()["access_token"]


def keycloak_get(
    kc_url: str, realm: str, token: str, path: str, verify_ssl: bool = True
) -> Any:
    try:
        resp = requests.get(
            f"{kc_url}/admin/realms/{realm}{path}",
            headers={"Authorization": f"Bearer {token}"},
            timeout=15,
            verify=verify_ssl,
        )
        return resp.json() if resp.text.strip() else None
    except Exception:
        return None


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Sync Keycloak groups → Grafana teams"
    )
    parser.add_argument("teams_yaml", help="Path to teams YAML file")
    parser.add_argument("--grafana-url", default=os.environ.get("GRAFANA_URL", ""))
    parser.add_argument("--grafana-auth", default=os.environ.get("GRAFANA_AUTH", ""))
    parser.add_argument("--keycloak-url", default=os.environ.get("KEYCLOAK_URL", ""))
    parser.add_argument(
        "--keycloak-realm", default=os.environ.get("KEYCLOAK_REALM", "grafana-realm")
    )
    parser.add_argument("--keycloak-user", default=os.environ.get("KEYCLOAK_USER", ""))
    parser.add_argument("--keycloak-pass", default=os.environ.get("KEYCLOAK_PASS", ""))
    parser.add_argument(
        "--dry-run",
        action="store_true",
        default=os.environ.get("DRY_RUN", "false").lower() == "true",
    )
    parser.add_argument(
        "--insecure",
        action="store_true",
        help="Disable SSL verification for Keycloak connections (matches original curl -k behavior)",
    )
    args = parser.parse_args()

    teams_yaml_path = Path(args.teams_yaml)
    if not teams_yaml_path.is_file():
        print(
            f"{Colors.RED}Error: teams YAML file required as first argument{Colors.NC}",
            file=sys.stderr,
        )
        sys.exit(1)

    # Validate required args
    required = {
        "GRAFANA_URL": args.grafana_url,
        "GRAFANA_AUTH": args.grafana_auth,
        "KEYCLOAK_URL": args.keycloak_url,
        "KEYCLOAK_USER": args.keycloak_user,
        "KEYCLOAK_PASS": args.keycloak_pass,
    }
    for name, val in required.items():
        if not val:
            print(f"{Colors.RED}Error: {name} is required{Colors.NC}", file=sys.stderr)
            sys.exit(1)

    grafana_url: str = args.grafana_url
    grafana_auth: str = args.grafana_auth
    kc_url: str = args.keycloak_url
    kc_realm: str = args.keycloak_realm
    kc_user: str = args.keycloak_user
    kc_pass: str = args.keycloak_pass
    dry_run: bool = args.dry_run
    verify_ssl: bool = not args.insecure

    if dry_run:
        print(f"{Colors.YELLOW}DRY RUN — no changes will be made{Colors.NC}")

    print(f"{Colors.BLUE}Team Sync{Colors.NC} — syncing Keycloak groups → Grafana teams")
    print(f"  Grafana:  {grafana_url}")
    print(f"  Keycloak: {kc_url}/realms/{kc_realm}")
    print()

    # Get Keycloak token
    try:
        kc_token = get_keycloak_token(kc_url, kc_user, kc_pass, verify_ssl=verify_ssl)
    except Exception as e:
        print(f"{Colors.RED}Failed to get Keycloak token: {e}{Colors.NC}", file=sys.stderr)
        sys.exit(1)

    # Load teams.yaml
    with open(teams_yaml_path) as f:
        config = yaml.safe_load(f)

    teams = config.get("teams", [])
    teams_with_groups = [t for t in teams if t.get("external_groups")]

    if not teams_with_groups:
        print("  No teams with external_groups configured — nothing to sync")
        sys.exit(0)

    print(f"  Found {len(teams_with_groups)} team(s) with external_groups mappings\n")

    # Build Keycloak group map
    kc_groups = keycloak_get(kc_url, kc_realm, kc_token, "/groups?max=200", verify_ssl=verify_ssl) or []
    kc_group_map: dict[str, str] = {g["name"]: g["id"] for g in kc_groups}

    # Grafana session
    g_session = make_grafana_session(grafana_auth)

    # Get all Grafana orgs
    grafana_orgs = grafana_get(g_session, grafana_url, "/api/orgs") or []
    org_name_to_id: dict[str, int] = {o["name"]: o["id"] for o in grafana_orgs}

    added = 0
    removed = 0
    skipped = 0
    errors = 0

    for team in teams_with_groups:
        team_name: str = team["name"]
        ext_groups: list[str] = team["external_groups"]
        org_name: str = team.get("org", "Main Org.")
        org_id: int | None = team.get("orgId") or org_name_to_id.get(org_name)

        if not org_id:
            print(f"  {Colors.RED}✗{Colors.NC} {team_name}: cannot resolve org '{org_name}'")
            errors += 1
            continue

        # Find Grafana team ID
        teams_resp = grafana_get(
            g_session, grafana_url,
            f"/api/teams/search?name={urlquote(team_name)}&perpage=100",
            org_id=org_id,
        )
        grafana_teams = teams_resp.get("teams", []) if teams_resp else []
        matching = [t for t in grafana_teams if t["name"] == team_name]

        if not matching:
            print(f"  {Colors.RED}✗{Colors.NC} {team_name}: not found in Grafana org {org_id}")
            errors += 1
            continue

        grafana_team_id: int = matching[0]["id"]

        # Current team members
        current_members = (
            grafana_get(g_session, grafana_url, f"/api/teams/{grafana_team_id}/members", org_id=org_id) or []
        )
        current_user_ids: set[int] = {m["userId"] for m in current_members}

        # Org-scoped users
        org_users = grafana_get(g_session, grafana_url, "/api/org/users", org_id=org_id) or []
        login_to_user: dict[str, dict] = {}
        email_to_user: dict[str, dict] = {}
        for u in org_users:
            login_to_user[u["login"].lower()] = u
            if u.get("email"):
                email_to_user[u["email"].lower()] = u

        # Global Grafana users
        all_grafana_users: list[dict] = []
        page = 1
        while True:
            batch = grafana_get(g_session, grafana_url, f"/api/users/search?perpage=200&page={page}") or {}
            users_batch = batch.get("users", [])
            all_grafana_users.extend(users_batch)
            if len(users_batch) < 200:
                break
            page += 1

        global_login_to_user: dict[str, dict] = {}
        global_email_to_user: dict[str, dict] = {}
        for u in all_grafana_users:
            global_login_to_user[u["login"].lower()] = u
            if u.get("email"):
                global_email_to_user[u["email"].lower()] = u

        # Desired members from Keycloak groups
        desired_user_ids: set[int] = set()
        desired_users: dict[int, str] = {}

        for group_name in ext_groups:
            kc_group_id = kc_group_map.get(group_name)
            if not kc_group_id:
                print(
                    f"  {Colors.YELLOW}⚠{Colors.NC} {team_name}:"
                    f" Keycloak group '{group_name}' not found — skipped"
                )
                continue

            kc_members = (
                keycloak_get(kc_url, kc_realm, kc_token, f"/groups/{kc_group_id}/members?max=500", verify_ssl=verify_ssl) or []
            )
            for km in kc_members:
                username = km.get("username", "").lower()
                email = km.get("email", "").lower()

                grafana_user = login_to_user.get(username) or email_to_user.get(email)
                if not grafana_user:
                    global_user = global_login_to_user.get(username) or global_email_to_user.get(email)
                    if global_user:
                        gf_login = global_user["login"]
                        print(
                            f"    {Colors.YELLOW}⚠{Colors.NC} {gf_login} exists in Grafana but not in"
                            f" org {org_id} — must log in via SSO to get org mapping"
                        )
                    else:
                        if username or email:
                            print(
                                f"    {Colors.DIM}⊘ KC:{username or email}"
                                f" not in Grafana — must log in via SSO first{Colors.NC}"
                            )
                    continue

                desired_user_ids.add(grafana_user["userId"])
                desired_users[grafana_user["userId"]] = grafana_user["login"]

        # Sync
        to_add = desired_user_ids - current_user_ids
        to_remove = current_user_ids - desired_user_ids

        if not to_add and not to_remove:
            print(
                f"  {Colors.GREEN}✓{Colors.NC} {team_name} (org {org_id}):"
                f" in sync ({len(current_user_ids)} members)"
            )
            skipped += 1
            continue

        print(
            f"  {Colors.BLUE}↻{Colors.NC} {team_name} (org {org_id}):"
            f" +{len(to_add)} -{len(to_remove)} members"
        )

        for uid in to_add:
            uname = desired_users.get(uid, f"userId={uid}")
            if dry_run:
                print(f"    [DRY] Would add {uname}")
            else:
                status, resp = grafana_post(
                    g_session, grafana_url,
                    f"/api/teams/{grafana_team_id}/members",
                    {"userId": uid},
                    org_id=org_id,
                )
                if 200 <= status < 300:
                    print(f"    {Colors.GREEN}+{Colors.NC} {uname}")
                    added += 1
                else:
                    print(f"    {Colors.RED}✗{Colors.NC} {uname}: HTTP {status} {resp}")
                    errors += 1

        for uid in to_remove:
            uname = next(
                (m["login"] for m in current_members if m["userId"] == uid),
                f"userId={uid}",
            )
            if dry_run:
                print(f"    [DRY] Would remove {uname}")
            else:
                status, resp = grafana_delete(
                    g_session, grafana_url,
                    f"/api/teams/{grafana_team_id}/members/{uid}",
                    org_id=org_id,
                )
                if 200 <= status < 300:
                    print(f"    {Colors.RED}-{Colors.NC} {uname}")
                    removed += 1
                else:
                    print(f"    {Colors.RED}✗{Colors.NC} {uname}: HTTP {status} {resp}")
                    errors += 1

    # Summary
    print()
    if dry_run:
        total = len(teams_with_groups)
        print(f"  Dry run complete — {total} team(s) checked")
    else:
        print(
            f"  Done: +{added} added, -{removed} removed,"
            f" {skipped} unchanged, {errors} error(s)"
        )


if __name__ == "__main__":
    main()
