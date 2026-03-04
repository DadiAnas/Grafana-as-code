#!/usr/bin/env python3
"""
Drift Detection — Detect out-of-band changes to Grafana.

Runs terraform plan in check mode and reports if any resources have been
modified outside of Terraform (manual UI changes, API calls, etc.).

Usage:
    python scripts/drift_detect.py <env-name>
    make drift ENV=staging
"""
from __future__ import annotations

import argparse
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


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Detect out-of-band changes to Grafana via terraform plan"
    )
    parser.add_argument("env", help="Environment name")
    args = parser.parse_args()

    env: str = args.env
    project_root = Path(__file__).resolve().parent.parent

    print(f"{Colors.BOLD}{Colors.CYAN}")
    print("╔═══════════════════════════════════════════════════════════════╗")
    print(f"║          Drift Detection: {env}")
    print("╚═══════════════════════════════════════════════════════════════╝")
    print(f"{Colors.NC}")

    # Validate environment exists
    if not (project_root / "envs" / env / "terraform.tfvars").is_file():
        print(f"{Colors.RED}Error: Environment '{env}' not found{Colors.NC}")
        print(f"  Missing: envs/{env}/terraform.tfvars")
        sys.exit(1)

    print(f"{Colors.BLUE}Running terraform plan...{Colors.NC}")
    print()

    result = subprocess.run(
        [
            "terraform",
            f"-chdir={project_root / 'terraform'}",
            "plan",
            f"-var-file=../envs/{env}/terraform.tfvars",
            f"-var=environment={env}",
            "-detailed-exitcode",
            "-no-color",
            "-compact-warnings",
        ],
        capture_output=True,
        text=True,
        cwd=project_root,
    )

    plan_output = result.stdout + result.stderr
    plan_exit = result.returncode

    if plan_exit == 0:
        print(f"{Colors.GREEN}╔═══════════════════════════════════════════════════════════════╗{Colors.NC}")
        print(f"{Colors.GREEN}║  No drift detected — Grafana matches Terraform state{Colors.NC}")
        print(f"{Colors.GREEN}╚═══════════════════════════════════════════════════════════════╝{Colors.NC}")
        sys.exit(0)

    elif plan_exit == 2:
        print(f"{Colors.YELLOW}╔═══════════════════════════════════════════════════════════════╗{Colors.NC}")
        print(f"{Colors.YELLOW}║  ⚠️  DRIFT DETECTED — Resources differ from Terraform state{Colors.NC}")
        print(f"{Colors.YELLOW}╚═══════════════════════════════════════════════════════════════╝{Colors.NC}")
        print()

        adds = len(re.findall(r"# .* will be created", plan_output))
        changes = len(re.findall(r"# .* will be updated", plan_output))
        destroys = len(re.findall(r"# .* will be destroyed", plan_output))

        print("  Summary:")
        if adds > 0:
            print(f"    {Colors.GREEN}+ {adds} to add{Colors.NC}")
        if changes > 0:
            print(f"    {Colors.YELLOW}~ {changes} to change{Colors.NC}")
        if destroys > 0:
            print(f"    {Colors.RED}- {destroys} to destroy{Colors.NC}")
        print()

        print("  Changed resources:")
        changed = [
            line[4:]  # strip leading "  # "
            for line in plan_output.splitlines()
            if line.startswith("  # ")
        ]
        for line in changed[:20]:
            print(f"    {line}")
        print()

        print(f"  To see full details:")
        print(f"    make plan ENV={env}")
        print()
        print(f"  To reconcile (apply Terraform state):")
        print(f"    make apply ENV={env}")
        print()
        sys.exit(2)

    else:
        print(f"{Colors.RED}╔═══════════════════════════════════════════════════════════════╗{Colors.NC}")
        print(f"{Colors.RED}║  Error running drift detection{Colors.NC}")
        print(f"{Colors.RED}╚═══════════════════════════════════════════════════════════════╝{Colors.NC}")
        print()
        for line in plan_output.splitlines()[-20:]:
            print(line)
        sys.exit(1)


if __name__ == "__main__":
    main()
