#!/usr/bin/env python3
"""
List Environments — Show all configured environments.

Usage:
    python scripts/list_envs.py
    make list-envs
"""
from __future__ import annotations

import argparse
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
    parser = argparse.ArgumentParser(description="Show all configured environments")
    parser.parse_args()

    project_root = Path(__file__).resolve().parent.parent
    envs_dir = project_root / "envs"

    print(f"{Colors.BOLD}{Colors.CYAN}")
    print("╔═══════════════════════════════════════════════════════════════╗")
    print("║                  Configured Environments                     ║")
    print("╚═══════════════════════════════════════════════════════════════╝")
    print(f"{Colors.NC}")

    if not envs_dir.is_dir():
        print(f"  {Colors.YELLOW}No environments directory found.{Colors.NC}")
        print()
        print(f"  Create one with: {Colors.BOLD}make new-env NAME=<name>{Colors.NC}")
        sys.exit(0)

    envs = sorted([d.name for d in envs_dir.iterdir() if d.is_dir()])

    if not envs:
        print(f"  {Colors.YELLOW}No environments found.{Colors.NC}")
        print()
        print(f"  Create one with: {Colors.BOLD}make new-env NAME=<name>{Colors.NC}")
        sys.exit(0)

    count = 0
    for env in envs:
        env_path = envs_dir / env
        count += 1

        has_tfvars = (env_path / "terraform.tfvars").is_file()
        has_backend = (env_path / "backend.tfbackend").is_file()
        has_config = env_path.is_dir()
        has_dashboards = (env_path / "dashboards").is_dir()

        tfvars_icon = f"{Colors.GREEN}✓{Colors.NC}" if has_tfvars else "❌"
        backend_icon = f"{Colors.GREEN}✓{Colors.NC}" if has_backend else "❌"
        config_icon = f"{Colors.GREEN}✓{Colors.NC}" if has_config else "❌"
        dashboards_icon = f"{Colors.GREEN}✓{Colors.NC}" if has_dashboards else "❌"

        # Extract Grafana URL from tfvars
        grafana_url = f"{Colors.DIM}not set{Colors.NC}"
        tfvars_file = env_path / "terraform.tfvars"
        if tfvars_file.is_file():
            for line in tfvars_file.read_text().splitlines():
                line = line.strip()
                if line.startswith("grafana_url") and "=" in line:
                    url = line.split("=", 1)[1].strip().strip('"').strip()
                    if url:
                        grafana_url = url
                    break

        # Count dashboards
        dashboard_count = 0
        if has_dashboards:
            dashboard_count = len(list((env_path / "dashboards").rglob("*.json")))

        # Count config files
        config_count = len(list(env_path.rglob("*.yaml"))) if has_config else 0

        # Template marker
        template_label = (
            f" {Colors.DIM}(template){Colors.NC}" if env == "myenv" else ""
        )

        print(f"  {Colors.BOLD}{Colors.BLUE}{env}{Colors.NC}{template_label}")
        print(f"    Grafana URL:       {grafana_url}")
        print(
            f"    tfvars:     {tfvars_icon}   backend:    {backend_icon}"
            f"   config:     {config_icon}   dashboards: {dashboards_icon}"
        )
        print(f"    Config files: {config_count}     Dashboard JSON files: {dashboard_count}")
        print()

    print(f"  {Colors.DIM}────────────────────────────────────────────────{Colors.NC}")
    print(f"  {Colors.BOLD}Total: {count} environment(s){Colors.NC}")
    print()
    print(f"  {Colors.DIM}Commands:{Colors.NC}")
    print(f"    Create new:  {Colors.BOLD}make new-env NAME=<name>{Colors.NC}")
    print(f"    Delete:      {Colors.BOLD}make delete-env NAME=<name>{Colors.NC}")
    print(f"    Deploy:      {Colors.BOLD}make init ENV=<name> && make plan ENV=<name>{Colors.NC}")
    print()


if __name__ == "__main__":
    main()
