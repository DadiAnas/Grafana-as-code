#!/usr/bin/env python3
"""
Check Environment — Validate environment is ready for deployment.

Usage:
    python scripts/check_env.py <env-name>
    make check-env ENV=prod
"""
from __future__ import annotations

import argparse
import os
import re
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


ERRORS = 0
WARNINGS = 0


def pass_(msg: str) -> None:
    print(f"  {Colors.GREEN}PASS{Colors.NC}  {msg}")


def fail_(msg: str) -> None:
    global ERRORS
    print(f"  {Colors.RED}FAIL{Colors.NC}  {msg}")
    ERRORS += 1


def warn_(msg: str) -> None:
    global WARNINGS
    print(f"  {Colors.YELLOW}⚠️  WARN{Colors.NC}  {msg}")
    WARNINGS += 1


def info_(msg: str) -> None:
    print(f"  {Colors.BLUE}ℹ️  INFO{Colors.NC}  {msg}")


def main() -> None:
    global ERRORS, WARNINGS

    parser = argparse.ArgumentParser(
        description="Validate environment is ready for deployment"
    )
    parser.add_argument("env_name", help="Environment name")
    args = parser.parse_args()

    env_name: str = args.env_name
    project_root = Path(__file__).resolve().parent.parent

    print(f"{Colors.BOLD}{Colors.BLUE}")
    print("╔═══════════════════════════════════════════════════════════════╗")
    print(f"║          Environment Check: {env_name}")
    print("╚═══════════════════════════════════════════════════════════════╝")
    print(f"{Colors.NC}")

    # ── Required Files ──
    print(f"{Colors.BOLD}── Required Files ──{Colors.NC}")

    if (project_root / "envs" / env_name / "terraform.tfvars").is_file():
        pass_(f"envs/{env_name}/terraform.tfvars")
    else:
        fail_(f"envs/{env_name}/terraform.tfvars is missing")

    if (project_root / "envs" / env_name).is_dir():
        pass_(f"envs/{env_name}/ directory")
    else:
        fail_(f"envs/{env_name}/ directory is missing")

    if (project_root / "envs" / env_name / "dashboards").is_dir():
        pass_(f"envs/{env_name}/dashboards/ directory")
    else:
        fail_(f"envs/{env_name}/dashboards/ directory is missing")

    print()

    # ── Optional Files ──
    print(f"{Colors.BOLD}── Optional Files ──{Colors.NC}")

    if (project_root / "envs" / env_name / "backend.tfbackend").is_file():
        pass_(f"envs/{env_name}/backend.tfbackend")
    else:
        info_(f"envs/{env_name}/backend.tfbackend not found (using local state)")

    print()

    # ── Configuration Files ──
    print(f"{Colors.BOLD}── Configuration Files ──{Colors.NC}")

    # Flat files still kept at env root
    flat_config_files = [
        "organizations.yaml",
        "sso.yaml",
        "keycloak.yaml",
    ]

    for cfg in flat_config_files:
        if (project_root / "envs" / env_name / cfg).is_file():
            pass_(f"envs/{env_name}/{cfg}")
        else:
            warn_(f"envs/{env_name}/{cfg} is missing (shared config will apply)")

    # Per-org directory resources
    per_org_resources = ["datasources", "folders", "teams", "service_accounts", "alerting"]
    for resource in per_org_resources:
        resource_dir = project_root / "envs" / env_name / resource
        if resource_dir.is_dir():
            org_count = sum(1 for d in resource_dir.iterdir() if d.is_dir())
            pass_(f"envs/{env_name}/{resource}/  ({org_count} org dir(s))")
        else:
            warn_(f"envs/{env_name}/{resource}/ is missing (shared config will apply)")

    print()

    # ── Shared Configuration ──
    print(f"{Colors.BOLD}── Shared Configuration ──{Colors.NC}")

    for cfg in flat_config_files:
        if (project_root / "base" / cfg).is_file():
            pass_(f"base/{cfg}")
        else:
            fail_(f"base/{cfg} is missing!")

    for resource in per_org_resources:
        resource_dir = project_root / "base" / resource
        if resource_dir.is_dir():
            org_count = sum(1 for d in resource_dir.iterdir() if d.is_dir())
            pass_(f"base/{resource}/ ({org_count} org dir(s))")
        else:
            info_(f"base/{resource}/ not present (env-level config only)")

    print()

    # ── Variables Check ──
    print(f"{Colors.BOLD}── Variables Check ──{Colors.NC}")

    tfvars_file = project_root / "envs" / env_name / "terraform.tfvars"
    if tfvars_file.is_file():
        content = tfvars_file.read_text()

        grafana_url_match = re.search(r'^\s*grafana_url\s*=\s*"?([^"\n]+)"?', content, re.MULTILINE)
        if grafana_url_match:
            url = grafana_url_match.group(1).strip().strip('"')
            pass_(f"grafana_url = {url}")
        else:
            fail_("grafana_url is not set in tfvars")

        env_match = re.search(r'^\s*environment\s*=\s*"?([^"\n]+)"?', content, re.MULTILINE)
        if env_match:
            env_val = env_match.group(1).strip().strip('"')
            if env_val == env_name:
                pass_(f"environment = {env_val} (matches)")
            else:
                fail_(f"environment = {env_val} (expected '{env_name}')")
        else:
            fail_("environment is not set in tfvars")

        if re.search(r'^\s*vault_address\s*=', content, re.MULTILINE):
            pass_("vault_address is configured")
        else:
            warn_("vault_address is not set")

    print()

    # ── Dashboard Structure ──
    print(f"{Colors.BOLD}── Dashboard Structure ──{Colors.NC}")

    dashboards_dir = project_root / "envs" / env_name / "dashboards"
    if dashboards_dir.is_dir():
        org_dirs = sorted([d.name for d in dashboards_dir.iterdir() if d.is_dir()])
        if org_dirs:
            for org in org_dirs:
                json_count = len(list((dashboards_dir / org).rglob("*.json")))
                info_(f"envs/{env_name}/dashboards/{org}/ ({json_count} dashboard files)")
        else:
            warn_(f"No organization subdirectories in envs/{env_name}/dashboards/")

    base_dashboards = project_root / "base" / "dashboards"
    if base_dashboards.is_dir():
        shared_json = len(list(base_dashboards.rglob("*.json")))
        info_(f"base/dashboards/ ({shared_json} shared dashboard files)")

    print()

    # ── Vault Connectivity ──
    print(f"{Colors.BOLD}── Vault Connectivity ──{Colors.NC}")

    vault_addr = os.environ.get("VAULT_ADDR", "")
    if vault_addr:
        # Check if vault CLI is available
        vault_available = subprocess.run(
            ["which", "vault"], capture_output=True
        ).returncode == 0

        if vault_available:
            result = subprocess.run(
                ["vault", "status"], capture_output=True, text=True
            )
            if result.returncode == 0:
                pass_(f"Vault is reachable at {vault_addr}")
                kv_result = subprocess.run(
                    ["vault", "kv", "list", f"grafana/{env_name}/"],
                    capture_output=True, text=True,
                )
                if kv_result.returncode == 0:
                    pass_(f"Vault secrets exist at grafana/{env_name}/")
                else:
                    warn_(
                        f"No secrets found at grafana/{env_name}/ — run: make vault-setup ENV={env_name}"
                    )
            else:
                warn_(f"Vault at {vault_addr} is not reachable or sealed")
        else:
            info_("Vault CLI not installed — skipping connectivity check")
    else:
        info_("VAULT_ADDR not set — skipping Vault check")

    print()

    # ── Summary ──
    print(f"{Colors.BOLD}── Summary ──{Colors.NC}")
    if ERRORS == 0 and WARNINGS == 0:
        print(f"  {Colors.GREEN}{Colors.BOLD}Environment '{env_name}' is ready for deployment!{Colors.NC}")
    elif ERRORS == 0:
        print(
            f"  {Colors.YELLOW}{Colors.BOLD}⚠️  {WARNINGS} warning(s), but environment is deployable.{Colors.NC}"
        )
    else:
        print(
            f"  {Colors.RED}{Colors.BOLD}{ERRORS} error(s), {WARNINGS} warning(s) — fix before deploying.{Colors.NC}"
        )
    print()

    sys.exit(ERRORS)


if __name__ == "__main__":
    main()
