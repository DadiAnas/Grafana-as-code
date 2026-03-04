#!/usr/bin/env python3
"""Run setup_secrets.py for one or more environments.

Usage:
    python scripts/vault/setup_all_secrets.py <env1> [env2] [env3] ...

Example:
    python setup_all_secrets.py myenv staging production
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


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Set up Vault secrets for one or more environments"
    )
    parser.add_argument(
        "environments",
        nargs="+",
        help="Environment names (e.g., myenv staging production)",
    )
    args = parser.parse_args()

    vault_addr = os.environ.get("VAULT_ADDR", "")
    vault_token = os.environ.get("VAULT_TOKEN", "")
    if not vault_addr or not vault_token:
        print(
            f"{Colors.RED}Error: VAULT_ADDR and VAULT_TOKEN environment "
            f"variables must be set{Colors.NC}"
        )
        print()
        print("  export VAULT_ADDR='http://localhost:8200'")
        print("  export VAULT_TOKEN='your-vault-token'")
        sys.exit(1)

    envs: list[str] = args.environments
    script_dir = Path(__file__).resolve().parent
    setup_secrets_py = script_dir / "setup_secrets.py"

    print("==============================================")
    print("Setting up Vault secrets")
    print(f"Vault Address: {vault_addr}")
    print(f"Environments:  {' '.join(envs)}")
    print("==============================================")
    print()

    for env in envs:
        print("----------------------------------------------")
        print(f"Setting up: {env}")
        print("----------------------------------------------")
        subprocess.run(
            ["python3", str(setup_secrets_py), env],
            check=True,
        )
        print()

    print("==============================================")
    print("All environments configured!")
    print("==============================================")
    print()
    print("Next steps:")
    print("  1. Update actual secret values via setup_secrets.py or make vault-setup")
    for env in envs:
        print(f"  2. Verify: vault kv list grafana/{env}/")
        print(f"  3. Apply:  make plan ENV={env}")


if __name__ == "__main__":
    main()
