#!/usr/bin/env python3
"""Find Terraform resources that depend on Vault secrets and generate -replace flags.

Scans YAML configs for VAULT_SECRET_REQUIRED sentinels, maps them to Terraform
resource addresses, and outputs `terraform apply -replace=...` flags so that
resources whose secrets changed in Vault are force-updated.

Usage:
    python scripts/vault/vault_refresh.py <env> [--dry-run] [--apply]

Modes:
    --dry-run   Show which resources would be refreshed (default)
    --apply     Actually run terraform apply with -replace flags
"""
import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML is required. Run: pip install PyYAML")
    sys.exit(1)


_SENTINEL_RE = re.compile(r"^VAULT_SECRET_REQUIRED:([^:]+):(.+)$")

TF_DIR = "terraform"


class Colors:
    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    BLUE = "\033[0;34m"
    CYAN = "\033[0;36m"
    DIM = "\033[2m"
    NC = "\033[0m"


def scan_value(value, found: set[str]) -> None:
    """Recursively collect all Vault paths referenced in a YAML value."""
    if isinstance(value, str):
        m = _SENTINEL_RE.match(value)
        if m:
            found.add(m.group(1))
    elif isinstance(value, dict):
        for v in value.values():
            scan_value(v, found)
    elif isinstance(value, list):
        for item in value:
            scan_value(item, found)


def find_vault_resources(env: str) -> list[str]:
    """Scan YAML configs and return Terraform resource addresses that need refresh.

    Detects:
    - Contact points with VAULT_SECRET_REQUIRED in settings
    - Datasources with VAULT_SECRET_REQUIRED in secure_json_data or http_headers
    - SSO config with VAULT_SECRET_REQUIRED
    """
    env_dir = Path("envs") / env
    replace_addresses: list[str] = []
    seen: set[str] = set()

    # --- Contact Points ---
    for cp_file in sorted(env_dir.rglob("contact_points.yaml")):
        try:
            with open(cp_file) as f:
                data = yaml.safe_load(f)
            if not data:
                continue

            for cp in data.get("contactPoints", []):
                cp_name = cp.get("name", "")
                org = cp.get("org", "")
                for recv in cp.get("receivers", []):
                    settings = recv.get("settings", {})
                    vault_paths: set[str] = set()
                    scan_value(settings, vault_paths)
                    if vault_paths:
                        addr = f'module.alerting.grafana_contact_point.contact_points["{org}:{cp_name}"]'
                        if addr not in seen:
                            seen.add(addr)
                            replace_addresses.append(addr)
        except Exception as e:
            print(f"  {Colors.YELLOW}Warning: {cp_file}: {e}{Colors.NC}", file=sys.stderr)

    # --- Datasources ---
    for ds_file in sorted(env_dir.rglob("datasources.yaml")):
        try:
            with open(ds_file) as f:
                data = yaml.safe_load(f)
            if not data:
                continue

            for ds in data.get("datasources", []):
                ds_name = ds.get("name", "")
                ds_uid = ds.get("uid", ds_name)
                org = ds.get("org", "")
                vault_paths: set[str] = set()
                scan_value(ds.get("secure_json_data", {}), vault_paths)
                scan_value(ds.get("http_headers", {}), vault_paths)
                if vault_paths:
                    addr = f'module.datasources.grafana_data_source.datasources["{org}:{ds_uid}"]'
                    if addr not in seen:
                        seen.add(addr)
                        replace_addresses.append(addr)
        except Exception as e:
            print(f"  {Colors.YELLOW}Warning: {ds_file}: {e}{Colors.NC}", file=sys.stderr)

    # --- SSO ---
    sso_file = env_dir / "sso.yaml"
    if sso_file.exists():
        try:
            with open(sso_file) as f:
                data = yaml.safe_load(f)
            if data:
                vault_paths: set[str] = set()
                scan_value(data.get("sso", {}), vault_paths)
                if vault_paths:
                    addr = 'module.sso.grafana_sso_settings.generic_oauth[0]'
                    if addr not in seen:
                        seen.add(addr)
                        replace_addresses.append(addr)
        except Exception as e:
            print(f"  {Colors.YELLOW}Warning: {sso_file}: {e}{Colors.NC}", file=sys.stderr)

    return replace_addresses


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Refresh Terraform resources that depend on Vault secrets"
    )
    parser.add_argument("env", help="Environment name")
    parser.add_argument("--dry-run", action="store_true", default=False,
                        help="Show what would be refreshed (default)")
    parser.add_argument("--apply", action="store_true", default=False,
                        help="Actually run terraform apply with -replace flags")
    parser.add_argument("--auto-approve", action="store_true", default=False,
                        help="Skip interactive approval (for CI)")
    args = parser.parse_args()
    env = args.env

    env_dir = Path("envs") / env
    if not env_dir.exists():
        print(f"{Colors.RED}ERROR: Environment '{env}' does not exist.{Colors.NC}")
        sys.exit(1)

    print(f"=== Vault Secret Refresh: {env} ===")
    print()

    addresses = find_vault_resources(env)

    if not addresses:
        print(f"{Colors.GREEN}No resources reference Vault secrets — nothing to refresh.{Colors.NC}")
        return

    print(f"Found {Colors.CYAN}{len(addresses)}{Colors.NC} resource(s) with Vault secrets:")
    for addr in addresses:
        print(f"  • {addr}")
    print()

    # Build terraform command
    tf_var_file = f"../envs/{env}/terraform.tfvars"
    replace_flags = []
    for addr in addresses:
        replace_flags.extend(["-replace", addr])

    if args.apply:
        cmd = [
            "terraform", "-chdir=" + TF_DIR,
            "apply", "-var-file=" + tf_var_file,
            *replace_flags,
        ]
        if args.auto_approve:
            cmd.append("-auto-approve")
        print(f"{Colors.BLUE}Running:{Colors.NC} {' '.join(cmd)}")
        print()
        result = subprocess.run(cmd)
        sys.exit(result.returncode)
    else:
        # Dry-run: show the plan
        cmd = [
            "terraform", "-chdir=" + TF_DIR,
            "plan", "-var-file=" + tf_var_file,
            *replace_flags,
        ]
        if args.dry_run:
            print(f"{Colors.DIM}Would run:{Colors.NC}")
            print(f"  {' '.join(cmd)}")
            print()
            print(f"To apply: {Colors.CYAN}make vault-refresh ENV={env} APPLY=true{Colors.NC}")
        else:
            print(f"{Colors.BLUE}Running:{Colors.NC} {' '.join(cmd)}")
            print()
            result = subprocess.run(cmd)
            sys.exit(result.returncode)


if __name__ == "__main__":
    main()
