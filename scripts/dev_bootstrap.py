#!/usr/bin/env python3
"""
Dev Environment Bootstrap — Seed Vault with test secrets and create a Grafana
service account for Terraform to use.

Run after `docker compose up -d`.

Usage:
    python scripts/dev_bootstrap.py [env-name]
    python scripts/dev_bootstrap.py dev
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
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


def wait_for_service(name: str, url: str, max_attempts: int = 30) -> bool:
    """Wait for a service to become available. Returns True on success."""
    print(f"  Waiting for {name}...", end="", flush=True)
    for attempt in range(max_attempts):
        try:
            resp = requests.get(url, timeout=2)
            if resp.status_code < 500:
                print(f" {Colors.GREEN}OK{Colors.NC}")
                return True
        except Exception:
            pass
        time.sleep(1)
        print(".", end="", flush=True)
    print(f" {Colors.RED}FAILED{Colors.NC} (timeout after {max_attempts}s)")
    return False


def vault_run(args_list: list[str], env: dict[str, str] | None = None) -> subprocess.CompletedProcess:
    full_env = {**os.environ, **(env or {})}
    return subprocess.run(args_list, capture_output=True, text=True, env=full_env)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Bootstrap dev environment: seed Vault and create Grafana service account"
    )
    parser.add_argument("env", nargs="?", default="dev", help="Environment name (default: dev)")
    args = parser.parse_args()

    env: str = args.env

    vault_addr = os.environ.get("VAULT_ADDR", "http://localhost:8200")
    vault_token = os.environ.get("VAULT_TOKEN", "root")
    grafana_url = os.environ.get("GRAFANA_URL", "http://localhost:3000")
    grafana_user = os.environ.get("GRAFANA_USER", "admin")
    grafana_pass = os.environ.get("GRAFANA_PASS", "admin")
    mount = "grafana"

    project_root = Path(__file__).resolve().parent.parent

    print(f"{Colors.BOLD}{Colors.CYAN}")
    print("╔═══════════════════════════════════════════════════════════════╗")
    print("║          Bootstrapping Dev Environment")
    print("╚═══════════════════════════════════════════════════════════════╝")
    print(f"{Colors.NC}")

    # ── Wait for services ──
    if not wait_for_service("Grafana", f"{grafana_url}/api/health"):
        sys.exit(1)
    if not wait_for_service("Vault", f"{vault_addr}/v1/sys/health"):
        sys.exit(1)

    vault_env = {"VAULT_ADDR": vault_addr, "VAULT_TOKEN": vault_token}

    # ── 1. Setup Vault ──
    print()
    print(f"{Colors.BLUE}[1/3]{Colors.NC} Setting up Vault secrets...")

    # Enable KV v2 engine (ignore error if already enabled)
    vault_run(
        ["vault", "secrets", "enable", f"-path={mount}", "-version=2", "kv"],
        env=vault_env,
    )

    print(f"  {Colors.YELLOW}→{Colors.NC} Creating Grafana service account...")

    # Create service account via Grafana API
    session = requests.Session()
    session.auth = (grafana_user, grafana_pass)

    sa_id: str | None = None
    sa_token: str | None = None

    try:
        sa_resp = session.post(
            f"{grafana_url}/api/serviceaccounts",
            json={"name": "terraform-dev", "role": "Admin", "isDisabled": False},
            timeout=10,
        )
        sa_data = sa_resp.json()
        sa_id = str(sa_data.get("id", "")) if sa_data.get("id") else None
    except Exception:
        sa_id = None

    if sa_id and sa_id != "null":
        try:
            token_resp = session.post(
                f"{grafana_url}/api/serviceaccounts/{sa_id}/tokens",
                json={"name": "terraform-dev-token", "secondsToLive": 0},
                timeout=10,
            )
            token_data = token_resp.json()
            sa_token = token_data.get("key")
        except Exception:
            sa_token = None

    if sa_token:
        grafana_credential = sa_token
        print(f"  {Colors.GREEN}✓{Colors.NC} Service account created (ID: {sa_id})")
    else:
        grafana_credential = f"{grafana_user}:{grafana_pass}"
        print(f"  {Colors.YELLOW}⚠{Colors.NC}  Service account may already exist, using basic auth")
        print(f"  {Colors.YELLOW}⚠{Colors.NC}  Using basic auth: {grafana_user}:***")

    # Store Grafana auth in Vault
    vault_run(
        ["vault", "kv", "put", f"{mount}/{env}/grafana/auth", f"credentials={grafana_credential}"],
        env=vault_env,
    )
    print(f"  {Colors.GREEN}✓{Colors.NC} Vault: {mount}/{env}/grafana/auth")

    # ── 2. Store SSO mock secrets ──
    print()
    print(f"{Colors.BLUE}[2/3]{Colors.NC} Setting up mock SSO secrets...")

    vault_run(
        ["vault", "kv", "put", f"{mount}/{env}/sso/keycloak", "client_secret=dev-sso-client-secret"],
        env=vault_env,
    )
    print(f"  {Colors.GREEN}✓{Colors.NC} Vault: {mount}/{env}/sso/keycloak")

    # ── 3. Create dev environment config ──
    print()
    print(f"{Colors.BLUE}[3/3]{Colors.NC} Generating dev environment...")

    env_dir = project_root / "envs" / env
    if not env_dir.is_dir():
        new_env_script = Path(__file__).parent / "new-env.sh"
        subprocess.run(
            [
                "bash",
                str(new_env_script),
                env,
                f"--grafana-url={grafana_url}",
                f"--vault-addr={vault_addr}",
                f"--vault-mount={mount}",
            ],
            cwd=project_root,
        )
    else:
        print(f"  {Colors.YELLOW}⚠{Colors.NC}  Environment '{env}' already exists, skipping scaffolding")

    # ── Summary ──
    print()
    print(f"{Colors.GREEN}╔═══════════════════════════════════════════════════════════════╗{Colors.NC}")
    print(f"{Colors.GREEN}║  Dev environment bootstrapped successfully!{Colors.NC}")
    print(f"{Colors.GREEN}╚═══════════════════════════════════════════════════════════════╝{Colors.NC}")
    print()
    print("  Services:")
    print(f"    Grafana:   {grafana_url}  (admin/admin)")
    print(f"    Vault:     {vault_addr}  (token: root)")
    print()
    print("  Next steps:")
    print("    export VAULT_TOKEN=root")
    print(f"    make init  ENV={env}")
    print(f"    make plan  ENV={env}")
    print(f"    make apply ENV={env}")
    print()


if __name__ == "__main__":
    main()
