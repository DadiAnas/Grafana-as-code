#!/usr/bin/env python3
"""Bootstrap Vault secrets for Grafana.

Run this once to set up initial secrets structure.

Usage:
    python scripts/vault/bootstrap_secrets.py [environment]
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


class Colors:
    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    BLUE = "\033[0;34m"
    CYAN = "\033[0;36m"
    DIM = "\033[2m"
    BOLD = "\033[1m"
    NC = "\033[0m"


def _vault(*args: str, check: bool = True, capture: bool = False) -> subprocess.CompletedProcess:
    kwargs: dict = {"check": check}
    if capture:
        kwargs["stdout"] = subprocess.DEVNULL
        kwargs["stderr"] = subprocess.DEVNULL
    return subprocess.run(["vault", *args], **kwargs)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Bootstrap Vault secrets for Grafana"
    )
    parser.add_argument(
        "environment",
        nargs="?",
        default="npr",
        help="Environment name (default: npr)",
    )
    args = parser.parse_args()

    environment: str = args.environment

    if not os.environ.get("VAULT_ADDR") or not os.environ.get("VAULT_TOKEN"):
        print(f"{Colors.RED}Error: VAULT_ADDR and VAULT_TOKEN must be set{Colors.NC}")
        sys.exit(1)

    print(f"Setting up Vault secrets for environment: {environment}")

    # Enable KV v2 secrets engine if not already enabled
    result = _vault("secrets", "enable", "-path=grafana", "kv-v2",
                    check=False, capture=True)
    if result.returncode == 0:
        print("Secrets engine enabled")
    else:
        print("Secrets engine already enabled")

    # Apply policy
    script_dir = Path(__file__).resolve().parent
    policy_file = script_dir / "policies" / "grafana-terraform.hcl"
    print("Applying Vault policy...")
    _vault("policy", "write", "grafana-terraform", str(policy_file))

    # Create placeholder secrets
    print(f"Creating placeholder secrets for {environment}...")

    # Grafana admin credentials
    _vault("kv", "put", f"grafana/{environment}/grafana/auth",
           "credentials=admin:changeme")

    # Datasource credentials (examples)
    _vault("kv", "put", f"grafana/{environment}/datasources/prometheus-{environment}",
           "basicAuthPassword=prometheus-password")

    _vault("kv", "put", f"grafana/{environment}/datasources/loki-{environment}",
           "basicAuthPassword=loki-password")

    # Contact point credentials
    _vault("kv", "put",
           f"grafana/{environment}/alerting/contact-points/webhook-{environment}",
           "authorization_credentials=webhook-token")

    # SSO credentials
    _vault("kv", "put", f"grafana/{environment}/sso/keycloak",
           f"client_id=grafana-{environment}",
           "client_secret=keycloak-client-secret")

    print("Done! Remember to update placeholder values with actual secrets.")
    print()
    print("To verify secrets:")
    print(f"  vault kv get grafana/{environment}/grafana/auth")


if __name__ == "__main__":
    main()
