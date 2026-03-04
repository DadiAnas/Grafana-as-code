#!/usr/bin/env python3
"""Create required Vault secrets for a Grafana environment.

Usage:
    python scripts/vault/setup_secrets.py [env] [mount]
"""
from __future__ import annotations

import argparse
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


def _vault(*args: str, check: bool = True, suppress_output: bool = False) -> subprocess.CompletedProcess:
    kwargs: dict = {"check": check}
    if suppress_output:
        kwargs["stdout"] = subprocess.DEVNULL
        kwargs["stderr"] = subprocess.DEVNULL
    return subprocess.run(["vault", *args], **kwargs)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create required Vault secrets for a Grafana environment"
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

    vault_namespace = os.environ.get("VAULT_NAMESPACE", "")
    if vault_namespace:
        print(f"Using Vault namespace: {vault_namespace}")
        os.environ["VAULT_NAMESPACE"] = vault_namespace

    print(f"=== Setting up Vault secrets for environment: {env} ===")

    # Enable KV v2 secrets engine (skip if already enabled)
    _vault("secrets", "enable", f"-path={mount}", "-version=2", "kv",
           check=False, suppress_output=True)

    # Grafana authentication credentials
    print("Creating Grafana auth secret...")
    _vault("kv", "put", f"{mount}/{env}/grafana/auth",
           "credentials=your-grafana-api-key-or-service-account-token")

    print()
    print(f"=== Vault secrets for {env} created successfully ===")
    print()
    print(f"Verify with: vault kv list {mount}/{env}/")


if __name__ == "__main__":
    main()
