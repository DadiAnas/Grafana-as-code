#!/usr/bin/env python3
"""Create required Vault secrets for a Grafana environment by scanning configs.

Scans ALL YAML files under envs/<env>/ for values matching the sentinel pattern:
    VAULT_SECRET_REQUIRED:<vault-path>:<key>

Groups discovered secrets by Vault path and writes placeholder values to Vault.

Usage:
    python scripts/vault/setup_secrets.py [env]
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


# Sentinel pattern: VAULT_SECRET_REQUIRED:<path>:<key>
_SENTINEL_RE = re.compile(r"^VAULT_SECRET_REQUIRED:([^:]+):(.+)$")


class Colors:
    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    BLUE = "\033[0;34m"
    CYAN = "\033[0;36m"
    DIM = "\033[2m"
    NC = "\033[0m"


def _vault(*args: str, check: bool = True, suppress_output: bool = False) -> subprocess.CompletedProcess:
    kwargs: dict = {"check": check}
    if suppress_output:
        kwargs["stdout"] = subprocess.DEVNULL
        kwargs["stderr"] = subprocess.DEVNULL
    return subprocess.run(["vault", *args], **kwargs)


def parse_tfvars(env: str) -> dict:
    """Parse terraform.tfvars for vault_mount, vault_namespace, vault_address, etc."""
    tfvars_path = Path("envs") / env / "terraform.tfvars"

    vars_dict = {
        "vault_mount": "grafana",
        "vault_namespace": "",
        "vault_address": "http://localhost:8200",
        "vault_path_grafana_auth": "{env}/grafana/auth",
        "vault_path_keycloak": "{env}/keycloak/client",
        "environment": env,
    }

    # Booleans parsed separately
    bool_vars = {
        "use_vault": False,
    }

    if not tfvars_path.exists():
        vars_dict.update(bool_vars)
        return vars_dict

    content = tfvars_path.read_text()

    # Parse string variables: key = "value"
    str_pattern = re.compile(r'^([a-zA-Z0-9_]+)\s*=\s*"([^"]+)"', re.MULTILINE)
    for match in str_pattern.finditer(content):
        key, val = match.groups()
        if key in vars_dict:
            vars_dict[key] = val

    # Parse boolean variables: key = true/false
    bool_pattern = re.compile(r'^([a-zA-Z0-9_]+)\s*=\s*(true|false)', re.MULTILINE)
    for match in bool_pattern.finditer(content):
        key, val = match.groups()
        if key in bool_vars:
            bool_vars[key] = val == "true"

    vars_dict.update(bool_vars)
    return vars_dict


def is_keycloak_enabled(env: str) -> bool:
    """Check if keycloak is enabled from keycloak.yaml."""
    for config_path in [
        Path("envs") / env / "keycloak.yaml",
        Path("base") / "keycloak.yaml",
    ]:
        if config_path.exists():
            try:
                with open(config_path) as f:
                    data = yaml.safe_load(f)
                if data and isinstance(data, dict):
                    return data.get("keycloak", {}).get("enabled", False) is True
            except Exception:
                pass
    return False


def vault_secret_exists(mount: str, path: str) -> bool:
    """Check if a secret already exists in Vault."""
    result = _vault("kv", "get", f"{mount}/{path}",
                    check=False, suppress_output=True)
    return result.returncode == 0


def scan_value(value, found: dict[str, dict[str, str]]) -> None:
    """Recursively scan a YAML value for VAULT_SECRET_REQUIRED sentinels.

    Args:
        value: Any YAML value (str, dict, list, etc.)
        found: Dict mapping vault_path -> {key: "changeme_<key>"}
    """
    if isinstance(value, str):
        m = _SENTINEL_RE.match(value)
        if m:
            vault_path, secret_key = m.groups()
            if vault_path not in found:
                found[vault_path] = {}
            found[vault_path][secret_key] = f"changeme_{secret_key}"
    elif isinstance(value, dict):
        for v in value.values():
            scan_value(v, found)
    elif isinstance(value, list):
        for item in value:
            scan_value(item, found)


def scan_yaml_file(filepath: Path) -> dict[str, dict[str, str]]:
    """Scan a single YAML file for all VAULT_SECRET_REQUIRED sentinels.

    Returns:
        Dict mapping vault_path -> {key: placeholder_value}
    """
    found: dict[str, dict[str, str]] = {}
    try:
        with open(filepath) as f:
            data = yaml.safe_load(f)
        if data:
            scan_value(data, found)
    except Exception as e:
        print(f"  {Colors.YELLOW}Warning: Could not parse {filepath}: {e}{Colors.NC}")
    return found


def write_vault_secret(mount: str, path: str, fields: dict) -> bool:
    """Write a secret to Vault KV v2."""
    print(f"  → Writing: {mount}/{path}")
    args = ["kv", "put", f"{mount}/{path}"]
    for k, v in fields.items():
        args.append(f"{k}={v}")
    try:
        _vault(*args)
        return True
    except subprocess.CalledProcessError:
        print(f"  {Colors.RED}✗ Failed writing secret{Colors.NC} "
              "(ensure Vault is unsealed and VAULT_TOKEN is correct)")
        return False


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create required Vault secrets by scanning YAML configs for VAULT_SECRET_REQUIRED sentinels"
    )
    parser.add_argument("env", default="dev", nargs="?", help="Environment name")
    args = parser.parse_args()
    env = args.env

    env_dir = Path("envs") / env
    if not env_dir.exists():
        print(f"{Colors.RED}ERROR: Environment '{env}' does not exist.{Colors.NC}")
        sys.exit(1)

    print(f"=== Scanning YAML configs for Vault secrets: {env} ===")
    print()

    tfvars = parse_tfvars(env)

    vault_namespace = tfvars.get("vault_namespace", "")
    if vault_namespace:
        print(f"Using Vault namespace: {vault_namespace}")
        os.environ["VAULT_NAMESPACE"] = vault_namespace

    vault_address = tfvars.get("vault_address", "http://localhost:8200")
    os.environ["VAULT_ADDR"] = vault_address

    mount = tfvars["vault_mount"]
    use_vault = tfvars.get("use_vault", False)

    # Enable KV v2 secrets engine (skip if already enabled)
    try:
        _vault("secrets", "enable", f"-path={mount}", "-version=2", "kv",
               check=False, suppress_output=True)
    except Exception:
        pass

    # Also scan base/ configs (they might have sentinels too)
    base_dir = Path("base")
    scan_dirs = [env_dir]
    if base_dir.exists():
        scan_dirs.append(base_dir)

    # Scan all YAML files for sentinels
    all_secrets: dict[str, dict[str, str]] = {}
    files_scanned = 0
    files_with_secrets = 0

    for scan_dir in scan_dirs:
        for yaml_file in sorted(scan_dir.rglob("*.yaml")):
            files_scanned += 1
            file_secrets = scan_yaml_file(yaml_file)
            if file_secrets:
                files_with_secrets += 1
                rel_path = yaml_file.relative_to(scan_dir.parent if scan_dir == base_dir else Path("."))
                print(f"  {Colors.CYAN}Found secrets in:{Colors.NC} {rel_path}")
                for vault_path, keys in file_secrets.items():
                    print(f"    → {vault_path}: {', '.join(keys.keys())}")
                    if vault_path not in all_secrets:
                        all_secrets[vault_path] = {}
                    all_secrets[vault_path].update(keys)

    print()
    print(f"Scanned {files_scanned} file(s), found secrets in {files_with_secrets} file(s)")
    print(f"Total unique Vault paths: {len(all_secrets)}")
    print()

    # Write all discovered secrets to Vault
    success_count = 0
    total_count = len(all_secrets)

    if all_secrets:
        print("[Writing resource secrets to Vault]")
        for vault_path, fields in sorted(all_secrets.items()):
            if write_vault_secret(mount, vault_path, fields):
                success_count += 1
        print()

    # ── Provider-level auth secrets ─────────────────────────────────────────
    # When use_vault is true, create Grafana and Keycloak provider auth
    # secrets if they don't already exist.
    # ───────────────────────────────────────────────────────────────────────
    if use_vault:
        print("[Provider auth secrets]")

        # Grafana auth secret
        grafana_auth_path = tfvars["vault_path_grafana_auth"].replace("{env}", env)
        if vault_secret_exists(mount, grafana_auth_path):
            print(f"  {Colors.DIM}● {mount}/{grafana_auth_path} (already exists){Colors.NC}")
        else:
            print(f"  → Creating Grafana auth secret: {mount}/{grafana_auth_path}")
            grafana_auth_fields = {"credentials": "changeme_grafana_auth"}
            if write_vault_secret(mount, grafana_auth_path, grafana_auth_fields):
                success_count += 1
            total_count += 1
            print(f"  {Colors.YELLOW}⚠  Update with real credentials:{Colors.NC}")
            print(f"    vault kv put {mount}/{grafana_auth_path} credentials=\"admin:admin\"")

        # Keycloak auth secret (only if keycloak is enabled)
        use_keycloak = is_keycloak_enabled(env)
        if use_keycloak:
            keycloak_path = tfvars["vault_path_keycloak"].replace("{env}", env)
            if vault_secret_exists(mount, keycloak_path):
                print(f"  {Colors.DIM}● {mount}/{keycloak_path} (already exists){Colors.NC}")
            else:
                print(f"  → Creating Keycloak auth secret: {mount}/{keycloak_path}")
                keycloak_fields = {
                    "client_secret": "changeme_keycloak_client_secret",
                }
                if write_vault_secret(mount, keycloak_path, keycloak_fields):
                    success_count += 1
                total_count += 1
                print(f"  {Colors.YELLOW}⚠  Update with real credentials:{Colors.NC}")
                print(f"    vault kv put {mount}/{keycloak_path} client_secret=\"your-secret\"")
        else:
            print(f"  {Colors.DIM}● Keycloak not enabled — skipping{Colors.NC}")

        print()

    if total_count == 0:
        print(f"{Colors.GREEN}No secrets needed — nothing to do.{Colors.NC}")
        return

    print(f"{Colors.GREEN}=== Vault secrets for {env} created successfully ==={Colors.NC}")
    print(f"  {success_count}/{total_count} paths written")
    print()
    print(f"Verify with: vault kv list {mount}/")
    all_paths = list(all_secrets.keys())
    if use_vault:
        all_paths.append(tfvars["vault_path_grafana_auth"].replace("{env}", env))
        if is_keycloak_enabled(env):
            all_paths.append(tfvars["vault_path_keycloak"].replace("{env}", env))
    for vault_path in sorted(set(all_paths)):
        parent = "/".join(vault_path.split("/")[:-1])
        if parent:
            print(f"  vault kv list {mount}/{parent}/")


if __name__ == "__main__":
    main()
