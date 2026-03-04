#!/usr/bin/env python3
"""
Delete Environment — Cleanup Script.

Removes all scaffolded files for an environment.
This does NOT destroy Terraform-managed infrastructure — use `make destroy`
for that first!

Usage:
    python scripts/delete_env.py <env-name>
    python scripts/delete_env.py <env-name> --force
"""
from __future__ import annotations

import argparse
import shutil
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
        description="Remove all scaffolded files for an environment"
    )
    parser.add_argument("env_name", help="Environment name")
    parser.add_argument(
        "--force", "-f", action="store_true", help="Skip confirmation prompt"
    )
    args = parser.parse_args()

    env_name: str = args.env_name
    force: bool = args.force
    project_root = Path(__file__).resolve().parent.parent

    # Protect template environment
    if env_name == "myenv":
        print(
            f"{Colors.RED}Error: Cannot delete the template environment 'myenv'{Colors.NC}"
        )
        print("This is the reference template for creating new environments.")
        sys.exit(1)

    # Check if environment exists
    env_path = project_root / "envs" / env_name
    tfvars = env_path / "terraform.tfvars"
    backend = env_path / "backend.tfbackend"
    dashboards = env_path / "dashboards"
    tfplan = project_root / f"tfplan-{env_name}"

    env_exists = any([tfvars.is_file(), backend.is_file(), env_path.is_dir()])
    if not env_exists:
        print(f"{Colors.RED}Error: Environment '{env_name}' does not exist{Colors.NC}")
        sys.exit(1)

    # Show what will be deleted
    print()
    print(f"{Colors.BOLD}{Colors.RED}╔═══════════════════════════════════════════════════════════════╗{Colors.NC}")
    print(f"{Colors.BOLD}{Colors.RED}║    ⚠️  DELETE ENVIRONMENT: {env_name}{Colors.NC}")
    print(f"{Colors.BOLD}{Colors.RED}╚═══════════════════════════════════════════════════════════════╝{Colors.NC}")
    print()
    print(f"{Colors.BOLD}The following files will be {Colors.RED}permanently deleted{Colors.NC}{Colors.BOLD}:{Colors.NC}")
    print()

    total_files = 0
    if tfvars.is_file():
        print(f"  {Colors.RED}✗{Colors.NC} envs/{env_name}/terraform.tfvars")
        total_files += 1
    if backend.is_file():
        print(f"  {Colors.RED}✗{Colors.NC} envs/{env_name}/backend.tfbackend")
        total_files += 1
    if env_path.is_dir():
        config_count = sum(1 for f in env_path.rglob("*") if f.is_file())
        print(f"  {Colors.RED}✗{Colors.NC} envs/{env_name}/ {Colors.DIM}({config_count} files){Colors.NC}")
        total_files += config_count
    if dashboards.is_dir():
        dash_count = sum(1 for f in dashboards.rglob("*") if f.is_file())
        json_count = len(list(dashboards.rglob("*.json")))
        print(
            f"  {Colors.RED}✗{Colors.NC} envs/{env_name}/dashboards/ "
            f"{Colors.DIM}({dash_count} files, {json_count} dashboards){Colors.NC}"
        )
        total_files += dash_count
    if tfplan.is_file():
        print(f"  {Colors.RED}✗{Colors.NC} tfplan-{env_name}")
        total_files += 1

    print()
    print(f"  {Colors.BOLD}Total: {total_files} file(s) will be deleted{Colors.NC}")
    print()

    # Warning about infrastructure
    print(f"{Colors.YELLOW}{Colors.BOLD}⚠️  IMPORTANT:{Colors.NC}")
    print(f"{Colors.YELLOW}   This only deletes local scaffolding files.{Colors.NC}")
    print(f"{Colors.YELLOW}   If you have applied Terraform, the infrastructure still exists!{Colors.NC}")
    print(
        f"{Colors.YELLOW}   Run {Colors.BOLD}make destroy ENV={env_name}{Colors.NC}"
        f"{Colors.YELLOW} first to tear down resources.{Colors.NC}"
    )
    print()

    # Confirmation
    if force:
        print(f"{Colors.DIM}Skipping confirmation (--force){Colors.NC}")
    else:
        print(f"{Colors.BOLD}To confirm deletion, type the environment name: {Colors.RED}{env_name}{Colors.NC}")
        print()
        confirm = input("  ▸ ").strip()
        if confirm != env_name:
            print()
            print(f"{Colors.GREEN}Cancelled.{Colors.NC} No files were deleted.")
            sys.exit(0)

    print()

    # Delete files
    if tfvars.is_file():
        tfvars.unlink()
        print(f"  {Colors.GREEN}✓{Colors.NC} Removed envs/{env_name}/terraform.tfvars")
    if backend.is_file():
        backend.unlink()
        print(f"  {Colors.GREEN}✓{Colors.NC} Removed envs/{env_name}/backend.tfbackend")
    if env_path.is_dir():
        shutil.rmtree(env_path)
        print(f"  {Colors.GREEN}✓{Colors.NC} Removed envs/{env_name}/")
    if tfplan.is_file():
        tfplan.unlink()
        print(f"  {Colors.GREEN}✓{Colors.NC} Removed tfplan-{env_name}")

    print()
    print(f"{Colors.GREEN}{Colors.BOLD}Environment '{env_name}' has been deleted.{Colors.NC}")
    print()


if __name__ == "__main__":
    main()
