#!/usr/bin/env python3
# =============================================================================
# validate_config.py — Schema-validate all Grafana-as-Code YAML config files
# =============================================================================
# Usage:
#   python3 scripts/validate_config.py              # validate base/ + all envs/
#   python3 scripts/validate_config.py --env prod   # validate base/ + envs/prod/
#   python3 scripts/validate_config.py --base-only  # validate base/ only
#   python3 scripts/validate_config.py --strict     # fail on warnings too
#
# Exit codes:
#   0  all files valid
#   1  one or more files have schema errors
# =============================================================================

import argparse
import sys
from pathlib import Path

try:
    import yamale
except ImportError:
    print("ERROR: 'yamale' is not installed. Run: pip install yamale")
    sys.exit(1)

# ── Colour helpers ────────────────────────────────────────────────────────────


class C:
    PASS = "\033[0;32m"
    FAIL = "\033[0;31m"
    WARN = "\033[0;33m"
    INFO = "\033[0;34m"
    BOLD = "\033[1m"
    DIM  = "\033[2m"
    NC   = "\033[0m"


def c_pass(msg: str) -> None:
    print(f"  {C.PASS}✓{C.NC}  {msg}")


def c_fail(msg: str) -> None:
    print(f"  {C.FAIL}✗{C.NC}  {msg}")


def c_skip(msg: str) -> None:
    print(f"  {C.DIM}–{C.NC}  {C.DIM}{msg}{C.NC}")


def c_info(msg: str) -> None:
    print(f"  {C.INFO}ℹ{C.NC}  {msg}")


# ── Schema registry ───────────────────────────────────────────────────────────
#
# Maps a glob pattern (relative to a root dir like base/ or envs/<env>/) to a
# schema filename in schemas/.  The pattern is matched against discovered files.
#
# Pattern conventions:
#   - "organizations.yaml"                    → flat file at root
#   - "datasources/*/datasources.yaml"        → per-org subdir file
#   - "alerting/*/alert_rules.yaml"           → per-org alerting file

SCHEMA_MAP = {
    "organizations.yaml":                       "organizations.schema.yaml",
    "datasources/*/datasources.yaml":           "datasources.schema.yaml",
    "folders/*/folders.yaml":                   "folders.schema.yaml",
    "teams/*/teams.yaml":                       "teams.schema.yaml",
    "service_accounts/*/service_accounts.yaml": "service_accounts.schema.yaml",
    "alerting/*/alert_rules.yaml":              "alert_rules.schema.yaml",
    "alerting/*/contact_points.yaml":           "contact_points.schema.yaml",
    "alerting/*/notification_policies.yaml":    "notification_policies.schema.yaml",
}


def load_schemas(schemas_dir: Path) -> dict:
    """Load all schema objects upfront (yamale caches internally)."""
    loaded = {}
    for pattern, schema_file in SCHEMA_MAP.items():
        schema_path = schemas_dir / schema_file
        if not schema_path.exists():
            print(f"{C.WARN}⚠  Schema not found: {schema_path}{C.NC}")
            continue
        loaded[pattern] = yamale.make_schema(str(schema_path))
    return loaded


# ── Core validation ───────────────────────────────────────────────────────────


def validate_root(root: Path, schemas: dict) -> list[str]:
    """
    Validate all matching YAML files under `root` against their schemas.
    Returns list of failed file paths.
    """
    failures = []

    for pattern, schema in schemas.items():
        matched = sorted(root.glob(pattern))

        if not matched:
            # Nothing to validate for this pattern in this root — that's fine
            continue

        for yaml_file in matched:
            rel = yaml_file.relative_to(root.parent)
            try:
                data = yamale.make_data(str(yaml_file))
                yamale.validate(schema, data, strict=False)
                c_pass(str(rel))
            except yamale.YamaleError as exc:
                c_fail(str(rel))
                for result in exc.results:
                    for err in result.errors:
                        print(f"         {C.FAIL}→{C.NC} {err}")
                failures.append(str(yaml_file))

    return failures


# ── Entry point ───────────────────────────────────────────────────────────────


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Schema-validate Grafana-as-Code YAML configuration files"
    )
    parser.add_argument(
        "--env",
        metavar="ENV",
        help="Only validate this environment (default: all environments)",
    )
    parser.add_argument(
        "--base-only",
        action="store_true",
        help="Only validate base/ shared configs",
    )
    args = parser.parse_args()

    project_root = Path(__file__).resolve().parent.parent
    schemas_dir  = project_root / "schemas"

    if not schemas_dir.exists():
        print(f"{C.FAIL}ERROR:{C.NC} schemas/ directory not found at {schemas_dir}")
        sys.exit(1)

    print(f"\n{C.BOLD}{C.INFO}")
    print("╔══════════════════════════════════════════════════════════════╗")
    print("║              Grafana-as-Code — Config Validation             ║")
    print("╚══════════════════════════════════════════════════════════════╝")
    print(f"{C.NC}")

    schemas = load_schemas(schemas_dir)
    if not schemas:
        print(f"{C.FAIL}No schemas loaded — aborting.{C.NC}")
        sys.exit(1)

    all_failures: list[str] = []

    # ── Validate base/ ──────────────────────────────────────────────────────
    print(f"{C.BOLD}── base/ (shared config) ──{C.NC}")
    base_dir = project_root / "base"
    failures = validate_root(base_dir, schemas)
    all_failures.extend(failures)
    if not failures:
        c_info("All shared configs valid")
    print()

    if args.base_only:
        _summary(all_failures)
        return

    # ── Validate env(s) ─────────────────────────────────────────────────────
    if args.env:
        env_dirs = [project_root / "envs" / args.env]
    else:
        env_dirs = sorted((project_root / "envs").iterdir()) if (project_root / "envs").exists() else []

    for env_dir in env_dirs:
        if not env_dir.is_dir():
            print(f"{C.WARN}⚠  Environment not found: {env_dir}{C.NC}\n")
            continue

        print(f"{C.BOLD}── envs/{env_dir.name}/ ──{C.NC}")
        failures = validate_root(env_dir, schemas)
        all_failures.extend(failures)
        if not failures:
            c_info(f"All configs valid in {env_dir.name}")
        print()

    _summary(all_failures)


def _summary(failures: list[str]) -> None:
    print(f"{C.BOLD}── Summary ──{C.NC}")
    if not failures:
        print(f"  {C.PASS}{C.BOLD}All config files passed schema validation ✓{C.NC}\n")
        sys.exit(0)
    else:
        print(f"  {C.FAIL}{C.BOLD}{len(failures)} file(s) failed validation:{C.NC}")
        for f in failures:
            print(f"    {C.FAIL}•{C.NC} {f}")
        print()
        sys.exit(1)


if __name__ == "__main__":
    main()
