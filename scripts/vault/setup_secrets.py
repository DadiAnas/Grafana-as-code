#!/usr/bin/env python3
"""Create required Vault secrets for a Grafana environment by scanning configs.

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


class Colors:
    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    NC = "\033[0m"


def _vault(*args: str, check: bool = True, suppress_output: bool = False) -> subprocess.CompletedProcess:
    kwargs: dict = {"check": check}
    if suppress_output:
        kwargs["stdout"] = subprocess.DEVNULL
        kwargs["stderr"] = subprocess.DEVNULL
    return subprocess.run(["vault", *args], **kwargs)


def parse_tfvars(env: str) -> dict:
    tfvars_path = Path("envs") / env / "terraform.tfvars"

    # Defaults
    vars_dict = {
        "vault_mount": "grafana",
        "vault_namespace": "",
        "vault_path_grafana_auth": "{env}/grafana/auth",
        "vault_path_datasources": "{env}/datasources",
        "vault_path_contact_points": "{env}/alerting/contact-points",
        "vault_path_sso": "{env}/sso/keycloak",
        "vault_path_keycloak": "{env}/keycloak/client",
        "vault_path_service_accounts": "{env}/service-accounts",
    }

    if not tfvars_path.exists():
        return vars_dict

    content = tfvars_path.read_text()

    # Matches: key = "value"
    pattern = re.compile(r'^([a-zA-Z0-9_]+)\s*=\s*"([^"]+)"', re.MULTILINE)

    for match in pattern.finditer(content):
        key, val = match.groups()
        if key in vars_dict:
            vars_dict[key] = val

    # Resolve {env}
    for k, v in vars_dict.items():
        if isinstance(v, str):
            vars_dict[k] = v.replace("{env}", env)

    return vars_dict


def parse_vault_hint(hint: str) -> list[str]:
    """Parse comma separated fields from the end of a hint string.
    Hint looks like: '... at path/to/vault: field1, field2'
    """
    if ":" in hint:
        fields = hint.split(":", 1)[1].strip()
        return [f.strip() for f in fields.split(",") if f.strip()]
    return []


def write_vault_secret(mount: str, path: str, fields: dict) -> None:
    print(f"  → Writing: {mount}/{path}")
    args = ["kv", "put", f"{mount}/{path}"]
    for k, v in fields.items():
        args.append(f"{k}={v}")
    try:
        _vault(*args)
    except subprocess.CalledProcessError as e:
        print(f"  {Colors.RED}✗ Failed writing secret{Colors.NC} (ensure vaulted is unsealed and VAULT_TOKEN is correct)")


def main() -> None:
    parser = argparse.ArgumentParser(description="Create required Vault secrets")
    parser.add_argument("env", default="dev", nargs="?", help="Environment name")
    args = parser.parse_args()
    env = args.env

    env_dir = Path("envs") / env
    if not env_dir.exists():
        print(f"{Colors.RED}ERROR: Environment '{env}' does not exist.{Colors.NC}")
        sys.exit(1)

    print(f"=== Setting up Vault secrets for environment: {env} ===")

    tfvars = parse_tfvars(env)

    vault_namespace = tfvars.get("vault_namespace", "")
    if vault_namespace:
        print(f"Using Vault namespace: {vault_namespace}")
        os.environ["VAULT_NAMESPACE"] = vault_namespace

    vault_address = tfvars.get("vault_address", "http://localhost:8200")
    os.environ["VAULT_ADDR"] = vault_address

    mount = tfvars["vault_mount"]

    # Enable KV v2 secrets engine (skip if already enabled)
    try:
        _vault("secrets", "enable", f"-path={mount}", "-version=2", "kv",
               check=False, suppress_output=True)
    except Exception:
        pass

    # 1. Grafana auth
    print("\n[Grafana Core Auth]")
    write_vault_secret(mount, tfvars["vault_path_grafana_auth"], {
        "credentials": "admin:admin"
    })

    # 2. Keycloak / SSO
    if (env_dir / "sso.yaml").exists() or (env_dir / "keycloak.yaml").exists():
        print("\n[SSO & Keycloak]")
        write_vault_secret(mount, tfvars["vault_path_sso"], {
            "client_secret": "changeme_sso_secret"
        })
        write_vault_secret(mount, tfvars["vault_path_keycloak"], {
            "username": "admin",
            "password": "changeme_keycloak_pass",
            "client_secret": "changeme_provider_secret"
        })

    # 3. Datasources
    print("\n[Datasources]")
    ds_dir = env_dir / "datasources"
    if ds_dir.exists():
        for yaml_file in ds_dir.rglob("*.yaml"):
            try:
                with open(yaml_file) as f:
                    data = yaml.safe_load(f) or {}
                    datasources = data.get("datasources", [])
                    for ds in datasources:
                        if ds.get("use_vault"):
                            db_name = ds["name"]
                            fields_to_create = ["password"]
                            if "vault_secret_fields" in ds:
                                parsed = parse_vault_hint(ds["vault_secret_fields"])
                                if parsed:
                                    fields_to_create = parsed

                            field_dict = {f: f"changeme_{f}" for f in fields_to_create}
                            write_vault_secret(mount, f"{tfvars['vault_path_datasources']}/{db_name}", field_dict)
            except Exception as e:
                print(f"  {Colors.YELLOW}Warning: Could not parse {yaml_file}: {e}{Colors.NC}")

    # 4. Contact Points
    print("\n[Contact Points]")
    alert_dir = env_dir / "alerting"
    if alert_dir.exists():
        for yaml_file in alert_dir.rglob("contact_points.yaml"):
            try:
                with open(yaml_file) as f:
                    data = yaml.safe_load(f) or {}
                    cps = data.get("contactPoints", [])
                    for cp in cps:
                        cp_name = cp["name"]
                        needed_secrets = []
                        for recv in cp.get("receivers", []):
                            if "vault_secrets" in recv:
                                parsed = parse_vault_hint(recv["vault_secrets"])
                                if parsed:
                                    needed_secrets.extend(parsed)

                        # Only create vault secret if some receiver asked for it
                        if needed_secrets:
                            unique_secrets = sorted(set(needed_secrets))
                            field_dict = {s: f"changeme_{s}" for s in unique_secrets}
                            write_vault_secret(mount, f"{tfvars['vault_path_contact_points']}/{cp_name}", field_dict)

            except Exception as e:
                print(f"  {Colors.YELLOW}Warning: Could not parse {yaml_file}: {e}{Colors.NC}")

    print()
    print(f"{Colors.GREEN}=== Vault secrets for {env} created successfully ==={Colors.NC}")
    print()
    print(f"Verify with: vault kv list {mount}/{tfvars['vault_path_datasources']}")


if __name__ == "__main__":
    main()
