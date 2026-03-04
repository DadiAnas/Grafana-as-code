#!/usr/bin/env python3
"""
Dashboard Diff — Human-readable dashboard change summary.

Compares dashboard JSON files and shows a clean summary of what changed
(panels added/removed/modified, queries changed, etc.) instead of raw JSON.

Usage:
    python scripts/dashboard_diff.py <env-name>                   # vs git HEAD
    python scripts/dashboard_diff.py <env-name> --against=staging  # vs another env

Via Make:
    make dashboard-diff ENV=prod
"""
from __future__ import annotations

import argparse
import json
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


def load_dashboard(path: Path) -> dict:
    data = json.loads(path.read_text())
    return data.get("dashboard", data)


def load_dashboard_from_str(content: str) -> dict:
    data = json.loads(content)
    return data.get("dashboard", data)


def diff_dashboards(dash_a: dict, dash_b: dict, label_a: str = "new", label_b: str = "old") -> bool:
    """Print panel/variable/time differences between two dashboard dicts. Returns True if diffs found."""
    has_diff = False

    if dash_a.get("title") != dash_b.get("title"):
        print(f'      Title: "{dash_b.get("title")}" → "{dash_a.get("title")}"')
        has_diff = True

    panels_a = {
        p.get("title", f"panel-{p.get('id', '?')}"): p for p in dash_a.get("panels", [])
    }
    panels_b = {
        p.get("title", f"panel-{p.get('id', '?')}"): p for p in dash_b.get("panels", [])
    }

    added = set(panels_a) - set(panels_b)
    removed = set(panels_b) - set(panels_a)
    common = set(panels_a) & set(panels_b)

    for name in sorted(added):
        ptype = panels_a[name].get("type", "?")
        print(f'      {Colors.GREEN}+ Panel: "{name}" ({ptype}){Colors.NC}')
        has_diff = True

    for name in sorted(removed):
        ptype = panels_b[name].get("type", "?")
        print(f'      {Colors.RED}- Panel: "{name}" ({ptype}){Colors.NC}')
        has_diff = True

    for name in sorted(common):
        pa, pb = panels_a[name], panels_b[name]
        diffs: list[str] = []
        if pa.get("type") != pb.get("type"):
            diffs.append(f"type: {pb.get('type')} → {pa.get('type')}")
        if pa.get("datasource") != pb.get("datasource"):
            diffs.append("datasource changed")
        if json.dumps(pa.get("targets", []), sort_keys=True) != json.dumps(
            pb.get("targets", []), sort_keys=True
        ):
            diffs.append("queries modified")
        if pa.get("description") != pb.get("description"):
            diffs.append("description changed")
        if diffs:
            print(f'      {Colors.YELLOW}~ Panel: "{name}" ({", ".join(diffs)}){Colors.NC}')
            has_diff = True

    vars_a = {v.get("name", ""): v for v in dash_a.get("templating", {}).get("list", [])}
    vars_b = {v.get("name", ""): v for v in dash_b.get("templating", {}).get("list", [])}
    added_vars = set(vars_a) - set(vars_b)
    removed_vars = set(vars_b) - set(vars_a)
    for v in sorted(added_vars):
        print(f"      {Colors.GREEN}+ Variable: ${v}{Colors.NC}")
        has_diff = True
    for v in sorted(removed_vars):
        print(f"      {Colors.RED}- Variable: ${v}{Colors.NC}")
        has_diff = True

    if dash_a.get("time") != dash_b.get("time"):
        print("      Time range changed")
        has_diff = True

    return has_diff


def compare_against_env(
    project_root: Path, env: str, against: str, dash_dir: Path
) -> None:
    against_dir = project_root / "envs" / against / "dashboards"
    if not against_dir.is_dir():
        print(f"{Colors.RED}Error: envs/{against}/dashboards/ not found{Colors.NC}")
        sys.exit(1)

    print(f"  Comparing: {Colors.BOLD}{env}{Colors.NC} vs {Colors.BOLD}{against}{Colors.NC}")
    print()

    all_files: set[str] = set()
    for f in dash_dir.rglob("*.json"):
        all_files.add(str(f.relative_to(dash_dir)))
    for f in against_dir.rglob("*.json"):
        all_files.add(str(f.relative_to(against_dir)))

    has_changes = False
    for rel_path in sorted(all_files):
        file_a = dash_dir / rel_path
        file_b = against_dir / rel_path

        if not file_a.exists():
            print(f"  {Colors.RED}─{Colors.NC} {rel_path} {Colors.DIM}(only in {against}){Colors.NC}")
            has_changes = True
        elif not file_b.exists():
            print(f"  {Colors.GREEN}+{Colors.NC} {rel_path} {Colors.DIM}(only in {env}){Colors.NC}")
            has_changes = True
        elif file_a.read_text() != file_b.read_text():
            print(f"  {Colors.YELLOW}~{Colors.NC} {rel_path}")
            try:
                dash_a = load_dashboard(file_a)
                dash_b = load_dashboard(file_b)
                diff_dashboards(dash_a, dash_b)
            except Exception:
                pass
            print()
            has_changes = True

    if not has_changes:
        print(f"  {Colors.GREEN}No dashboard changes detected{Colors.NC}")


def compare_against_git(project_root: Path, env: str, dash_dir: Path) -> None:
    print(f"  Comparing: {Colors.BOLD}{env}{Colors.NC} dashboards vs {Colors.BOLD}git HEAD{Colors.NC}")
    print()

    # Changed/staged files
    changed_result = subprocess.run(
        ["git", "diff", "--name-status", "HEAD", "--", f"envs/{env}/dashboards/"],
        capture_output=True, text=True, cwd=project_root,
    )
    changed_files = changed_result.stdout.strip()

    # Untracked
    untracked_result = subprocess.run(
        ["git", "ls-files", "--others", "--exclude-standard", "--", f"envs/{env}/dashboards/"],
        capture_output=True, text=True, cwd=project_root,
    )
    untracked = untracked_result.stdout.strip()

    has_changes = False

    if changed_files:
        for line in changed_files.splitlines():
            parts = line.split("\t", 1)
            if len(parts) != 2:
                continue
            status, filepath = parts
            if status == "A":
                print(f"  {Colors.GREEN}+{Colors.NC} {filepath} {Colors.DIM}(added){Colors.NC}")
                has_changes = True
            elif status == "D":
                print(f"  {Colors.RED}-{Colors.NC} {filepath} {Colors.DIM}(deleted){Colors.NC}")
                has_changes = True
            elif status == "M":
                print(f"  {Colors.YELLOW}~{Colors.NC} {filepath}")
                try:
                    old_result = subprocess.run(
                        ["git", "show", f"HEAD:{filepath}"],
                        capture_output=True, text=True, cwd=project_root,
                    )
                    old_content = old_result.stdout
                    dash_b = load_dashboard_from_str(old_content)
                    dash_a = load_dashboard(project_root / filepath)
                    diffs: list[str] = []
                    panels_a = {
                        p.get("title", f"panel-{p.get('id','?')}"): p
                        for p in dash_a.get("panels", [])
                    }
                    panels_b = {
                        p.get("title", f"panel-{p.get('id','?')}"): p
                        for p in dash_b.get("panels", [])
                    }
                    for name in sorted(set(panels_a) - set(panels_b)):
                        print(f'      {Colors.GREEN}+ Panel: "{name}"{Colors.NC}')
                    for name in sorted(set(panels_b) - set(panels_a)):
                        print(f'      {Colors.RED}- Panel: "{name}"{Colors.NC}')
                    for name in sorted(set(panels_a) & set(panels_b)):
                        if json.dumps(panels_a[name], sort_keys=True) != json.dumps(
                            panels_b[name], sort_keys=True
                        ):
                            changes: list[str] = []
                            if panels_a[name].get("type") != panels_b[name].get("type"):
                                changes.append("type changed")
                            if json.dumps(
                                panels_a[name].get("targets", []), sort_keys=True
                            ) != json.dumps(panels_b[name].get("targets", []), sort_keys=True):
                                changes.append("queries modified")
                            if not changes:
                                changes.append("layout/style")
                            print(
                                f'      {Colors.YELLOW}~ Panel: "{name}"'
                                f' ({", ".join(changes)}){Colors.NC}'
                            )
                except Exception:
                    pass
                print()
                has_changes = True

    if untracked:
        for filepath in untracked.splitlines():
            print(f"  {Colors.GREEN}+{Colors.NC} {filepath} {Colors.DIM}(untracked){Colors.NC}")
            has_changes = True

    if not has_changes:
        print(f"  {Colors.GREEN}No dashboard changes detected{Colors.NC}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Human-readable dashboard change summary"
    )
    parser.add_argument("env", help="Environment name")
    parser.add_argument(
        "--against", metavar="ENV", help="Compare against another environment"
    )
    args = parser.parse_args()

    env: str = args.env
    against: str | None = args.against
    project_root = Path(__file__).resolve().parent.parent
    dash_dir = project_root / "envs" / env / "dashboards"

    if not dash_dir.is_dir():
        print(f"{Colors.RED}Error: envs/{env}/dashboards/ not found{Colors.NC}")
        sys.exit(1)

    print(f"{Colors.BOLD}{Colors.CYAN}")
    print("╔═══════════════════════════════════════════════════════════════╗")
    print(f"║          Dashboard Diff: {env}")
    print("╚═══════════════════════════════════════════════════════════════╝")
    print(f"{Colors.NC}")

    if against:
        compare_against_env(project_root, env, against, dash_dir)
    else:
        compare_against_git(project_root, env, dash_dir)

    print()


if __name__ == "__main__":
    main()
