#!/usr/bin/env python3
"""Verify required Vault secrets exist for an environment.

Usage:
    python scripts/vault/verify_secrets.py [environment] [mount]
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys


class Colors:
    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    BLUE = "\033[0;34m"
    CYAN = "\033[0;36m"
    DIM = "\033[2m"
    BOLD = "\033[1m"
    NC = "\033[0m"


def _vault_get_json(full_path: str) -> dict | None:
    result = subprocess.run(
        ["vault", "kv", "get", "-format=json", full_path],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return None
    return json.loads(result.stdout)


def check_secret(
    mount: str, path: str, description: str, errors: list[str]
) -> None:
    full_path = f"{mount}/{path}"
    data = _vault_get_json(full_path)
    if data is not None:
        print(f"  {Colors.GREEN}✓{Colors.NC} {description}")
        print(f"     Path: {full_path}")
    else:
        print(f"  {Colors.RED}✗{Colors.NC} {description} — MISSING")
        print(f"     Expected: {full_path}")
        errors.append(path)


def check_secret_key(
    mount: str,
    path: str,
    key: str,
    description: str,
    errors: list[str],
) -> None:
    full_path = f"{mount}/{path}"
    data = _vault_get_json(full_path)
    value = ""
    if data is not None:
        value = data.get("data", {}).get("data", {}).get(key, "")
    if value:
        print(f"  {Colors.GREEN}✓{Colors.NC} {description}")
        print(f"     Path: {full_path} (key: {key})")
    else:
        print(f"  {Colors.RED}✗{Colors.NC} {description} — MISSING or EMPTY")
        print(f"     Expected: {full_path} with key '{key}'")
        errors.append(f"{path}:{key}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Verify required Vault secrets exist for an environment"
    )
    parser.add_argument(
        "env",
        nargs="?",
        default="myenv",
        help="Environment name (default: myenv)",
    )
    parser.add_argument(
        "mount",
        nargs="?",
        default="grafana",
        help="Vault KV mount path (default: grafana)",
    )
    args = parser.parse_args()

    env: str = args.env
    mount: str = args.mount

    if not os.environ.get("VAULT_ADDR") or not os.environ.get("VAULT_TOKEN"):
        print(
            f"{Colors.RED}Error: VAULT_ADDR and VAULT_TOKEN environment "
            f"variables must be set{Colors.NC}"
        )
        sys.exit(1)

    vault_addr = os.environ.get("VAULT_ADDR", "")

    print("==============================================")
    print(f"Verifying Vault secrets for: {env}")
    print(f"Vault Address: {vault_addr}")
    print(f"Mount path:    {mount}")
    print("==============================================")
    print()

    errors: list[str] = []

    print("--- Grafana Credentials ---")
    check_secret_key(
        mount,
        f"{env}/grafana/auth",
        "credentials",
        "Grafana API key / service account token",
        errors,
    )

    print()
    print("--- Datasource Credentials (if any use_vault: true) ---")
    print("  \u2139\ufe0f  Uncomment datasource checks in verify-secrets.py for your setup")

    print()
    print("--- SSO Credentials (if sso.enabled: true) ---")
    print("  \u2139\ufe0f  Uncomment SSO check if you use SSO")

    print()
    print("==============================================")
    if not errors:
        print(f"  {Colors.GREEN}All required secrets verified!{Colors.NC}")
    else:
        print(f"  {Colors.RED}{len(errors)} secret(s) missing{Colors.NC}")
        print()
        print(f"  Run: python3 scripts/vault/setup_secrets.py {env}")
    print("==============================================")

    sys.exit(len(errors))


if __name__ == "__main__":
    main()
