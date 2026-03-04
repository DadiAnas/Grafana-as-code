#!/usr/bin/env python3
"""Rotate a specific secret in Vault.

Usage:
    python scripts/vault/rotate_secret.py <environment> <secret-type> <secret-name>

Arguments:
    environment   npr, preprod, or prod
    secret-type   grafana, datasource, contact-point, or sso
    secret-name   Name of the secret to rotate

Examples:
    python rotate_secret.py npr datasource PostgreSQL
    python rotate_secret.py prod contact-point webhook-critical
    python rotate_secret.py preprod grafana auth
    python rotate_secret.py prod sso keycloak
"""
from __future__ import annotations

import argparse
import getpass
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


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Rotate a specific secret in Vault",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "secret-type options: grafana, datasource, contact-point, sso\n"
            "environment options: npr, preprod, prod"
        ),
    )
    parser.add_argument("environment", help="Environment: npr, preprod, or prod")
    parser.add_argument(
        "secret_type",
        help="Secret type: grafana, datasource, contact-point, or sso",
    )
    parser.add_argument("secret_name", help="Name of the secret to rotate")
    args = parser.parse_args()

    env: str = args.environment
    secret_type: str = args.secret_type
    secret_name: str = args.secret_name
    mount = "grafana"

    # Validate environment
    valid_envs = {"npr", "preprod", "prod"}
    if env not in valid_envs:
        print(
            f"{Colors.RED}Error: Invalid environment '{env}'. "
            f"Must be npr, preprod, or prod.{Colors.NC}"
        )
        sys.exit(1)

    # Check Vault env vars
    if not os.environ.get("VAULT_ADDR") or not os.environ.get("VAULT_TOKEN"):
        print(
            f"{Colors.RED}Error: VAULT_ADDR and VAULT_TOKEN environment "
            f"variables must be set{Colors.NC}"
        )
        sys.exit(1)

    # Map secret type to path
    type_to_path: dict[str, str] = {
        "grafana": f"{env}/grafana/{secret_name}",
        "datasource": f"{env}/datasources/{secret_name}",
        "contact-point": f"{env}/alerting/contact-points/{secret_name}",
        "sso": f"{env}/sso/{secret_name}",
    }
    if secret_type not in type_to_path:
        print(f"{Colors.RED}Error: Invalid secret-type '{secret_type}'{Colors.NC}")
        print("Must be: grafana, datasource, contact-point, or sso")
        sys.exit(1)

    secret_path = type_to_path[secret_type]

    print("==============================================")
    print(f"Rotating secret: {mount}/{secret_path}")
    print("==============================================")

    # Check secret exists
    data = _vault_get_json(f"{mount}/{secret_path}")
    if data is None:
        print(
            f"{Colors.RED}Error: Secret does not exist at "
            f"{mount}/{secret_path}{Colors.NC}"
        )
        sys.exit(1)

    current_data: dict[str, str] = data.get("data", {}).get("data", {})
    keys = list(current_data.keys())

    print()
    print("Current secret keys:")
    for key in keys:
        print(f"  - {key}")

    print()
    print("Enter new values for each key (leave empty to keep current value):")
    print()

    new_data: dict[str, str] = {}
    for key in keys:
        current_value = current_data[key]
        new_value = getpass.getpass(
            f"New value for '{key}' (hidden, press Enter to keep current): "
        )
        new_data[key] = new_value if new_value else current_value

    print()
    print("Updating secret...")
    kv_args = [f"{k}={v}" for k, v in new_data.items()]
    subprocess.run(
        ["vault", "kv", "put", f"{mount}/{secret_path}", *kv_args],
        check=True,
    )

    print()
    print("==============================================")
    print(" Secret rotated successfully!")
    print("==============================================")
    print()
    print("Next steps:")
    print("  1. Re-run Terraform to apply the new credentials:")
    print(f"     terraform apply -var-file envs/{env}/terraform.tfvars")
    print("  2. Verify the changes in Grafana")
    print("  3. Update any external systems using the old credentials")


if __name__ == "__main__":
    main()
