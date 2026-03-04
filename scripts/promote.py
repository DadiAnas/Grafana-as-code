#!/usr/bin/env python3
"""
Promote Environment — Copy/diff configs between environments.

Promotes configuration from one environment to another. Useful for
moving tested changes from staging → production.

Usage:
    python scripts/promote.py <from-env> <to-env>
    python scripts/promote.py staging prod               # copy staging to prod
    python scripts/promote.py staging prod --diff-only   # just show differences

Via Make:
    make promote FROM=staging TO=prod
"""
from __future__ import annotations

import argparse
import shutil
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
        description="Promote configuration from one environment to another"
    )
    parser.add_argument("from_env", metavar="from-env", help="Source environment")
    parser.add_argument("to_env", metavar="to-env", help="Target environment")
    parser.add_argument(
        "--diff-only", action="store_true", help="Only show differences, no changes"
    )
    args = parser.parse_args()

    from_env: str = args.from_env
    to_env: str = args.to_env
    diff_only: bool = args.diff_only

    project_root = Path(__file__).resolve().parent.parent
    from_config = project_root / "envs" / from_env
    to_config = project_root / "envs" / to_env
    from_dashboards = from_config / "dashboards"
    to_dashboards = to_config / "dashboards"

    print(f"{Colors.BOLD}{Colors.CYAN}")
    print("╔═══════════════════════════════════════════════════════════════╗")
    print(f"║          Promote: {from_env} → {to_env}")
    print("╚═══════════════════════════════════════════════════════════════╝")
    print(f"{Colors.NC}")

    # Validate source exists
    if not from_config.is_dir():
        print(f"{Colors.RED}Error: Source environment '{from_env}' not found{Colors.NC}")
        print(f"  Missing: envs/{from_env}/")
        sys.exit(1)

    # ── Configuration differences ──
    print(f"{Colors.BLUE}Configuration differences:{Colors.NC}")
    print()

    has_diff = False

    # Files only in from_env
    for file in sorted(from_config.rglob("*.yaml")):
        rel_path = file.relative_to(from_config)
        to_file = to_config / rel_path

        if not to_file.exists():
            print(f"  {Colors.GREEN}+ {rel_path}{Colors.NC} (new — only in {from_env})")
            has_diff = True
        elif file.read_bytes() != to_file.read_bytes():
            print(f"  {Colors.YELLOW}~ {rel_path}{Colors.NC} (modified)")
            result = subprocess.run(
                ["diff", "--color=always", "-u", str(to_file), str(file)],
                capture_output=True, text=True,
            )
            for line in result.stdout.splitlines()[:30]:
                print(f"    {line}")
            print()
            has_diff = True

    # Files only in to_env
    if to_config.is_dir():
        for file in sorted(to_config.rglob("*.yaml")):
            rel_path = file.relative_to(to_config)
            from_file = from_config / rel_path
            if not from_file.exists():
                print(
                    f"  {Colors.RED}- {rel_path}{Colors.NC}"
                    f" (only in {to_env}, would be kept)"
                )
                has_diff = True

    # Dashboard differences
    if from_dashboards.is_dir():
        print()
        print(f"{Colors.BLUE}Dashboard differences:{Colors.NC}")
        print()
        for file in sorted(from_dashboards.rglob("*.json")):
            rel_path = file.relative_to(from_dashboards)
            to_file = to_dashboards / rel_path
            if not to_file.exists():
                print(f"  {Colors.GREEN}+ {rel_path}{Colors.NC} (new)")
                has_diff = True
            elif file.read_bytes() != to_file.read_bytes():
                print(f"  {Colors.YELLOW}~ {rel_path}{Colors.NC} (modified)")
                has_diff = True

    if not has_diff:
        print(
            f"  {Colors.GREEN}No differences found — environments are in sync{Colors.NC}"
        )
        sys.exit(0)

    # Diff-only mode stops here
    if diff_only:
        print()
        print(f"{Colors.DIM}  (--diff-only mode, no changes applied){Colors.NC}")
        sys.exit(0)

    # ── Confirm promotion ──
    print()
    print(
        f"{Colors.YELLOW}⚠  This will overwrite envs/{to_env}/ with envs/{from_env}/{Colors.NC}"
    )
    print(
        f"   envs/{to_env}/dashboards/ will also be synced"
        f" from envs/{from_env}/dashboards/"
    )
    print()
    reply = input("  Continue? [y/N] ").strip().lower()
    print()

    if reply not in ("y", "yes"):
        print(f"{Colors.DIM}  Aborted.{Colors.NC}")
        sys.exit(0)

    # ── Perform promotion ──
    print()
    print(f"{Colors.BLUE}Promoting configuration...{Colors.NC}")

    (to_config / "alerting").mkdir(parents=True, exist_ok=True)
    to_dashboards.mkdir(parents=True, exist_ok=True)

    # Copy config files
    copied = 0
    for file in sorted(from_config.rglob("*.yaml")):
        rel_path = file.relative_to(from_config)
        to_file = to_config / rel_path
        to_file.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(file, to_file)
        print(f"  {Colors.GREEN}✓{Colors.NC} envs/{to_env}/{rel_path}")
        copied += 1

    # Copy dashboards
    dash_copied = 0
    if from_dashboards.is_dir():
        for file in sorted(from_dashboards.rglob("*.json")):
            rel_path = file.relative_to(from_dashboards)
            to_file = to_dashboards / rel_path
            to_file.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(file, to_file)
            dash_copied += 1
        print(f"  {Colors.GREEN}✓{Colors.NC} {dash_copied} dashboard(s) copied")

    print()
    print(f"{Colors.GREEN}╔═══════════════════════════════════════════════════════════════╗{Colors.NC}")
    print(f"{Colors.GREEN}║  Promotion complete: {from_env} → {to_env}{Colors.NC}")
    print(f"{Colors.GREEN}╚═══════════════════════════════════════════════════════════════╝{Colors.NC}")
    print()
    print(f"  Config files: {copied}")
    print(f"  Dashboards:   {dash_copied}")
    print()
    print("  Next steps:")
    print(f"    1. Review the promoted configs: git diff envs/{to_env}/")
    print("    2. Adjust env-specific values (URLs, credentials, etc.)")
    print("    3. Plan & apply:")
    print(f"       make plan  ENV={to_env}")
    print(f"       make apply ENV={to_env}")
    print()


if __name__ == "__main__":
    main()
