#!/usr/bin/env python3
"""Create New Environment — Scaffolding Script.

Creates all files needed for a new Grafana-as-Code environment.

Required:
    env_name    Environment name (positional argument)

Optional:
    --grafana-url=<url>         Grafana URL               (default: http://localhost:3000)
    --vault-addr=<url>          Vault address             (default: http://localhost:8200)
    --vault-mount=<path>        Vault KV mount            (default: grafana)
    --vault-namespace=<ns>      Vault Enterprise namespace
    --keycloak-url=<url>        Keycloak URL (enables SSO)
    --backend=<type>            Backend: s3, azurerm, gcs, gitlab
    --orgs=<org1,org2,...>      Custom organization names (comma-separated)
    --datasources=<ds1,ds2,...> Datasource presets (comma-separated)
    --dry-run                   Show what would be created without writing files

Usage via Make:
    make new-env NAME=staging
    make new-env NAME=prod GRAFANA_URL=https://grafana.example.com BACKEND=s3

Usage directly:
    python scripts/new_env.py staging
    python scripts/new_env.py prod --grafana-url=https://grafana.example.com --backend=s3
"""
from __future__ import annotations

import argparse
import os
import re
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


def _fill(template: str, **kwargs: str) -> str:
    """Replace @@KEY@@ placeholders in template with values."""
    result = template
    for key, val in kwargs.items():
        result = result.replace(f"@@{key}@@", val)
    return result


def _get_org_names(orgs: str, project_root: Path) -> list[str]:
    """Return list of org names from --orgs arg or base/organizations.yaml."""
    if orgs:
        return [o.strip() for o in orgs.split(",") if o.strip()]
    org_file = project_root / "base" / "organizations.yaml"
    if org_file.exists():
        names: list[str] = []
        for line in org_file.read_text().splitlines():
            if line.strip().startswith("#"):
                continue
            m = re.match(r"^\s+-\s+name:\s*[\"']?(.+?)[\"']?\s*$", line)
            if m:
                names.append(m.group(1))
        if names:
            return names
    return ["Main Organization"]


# ---------------------------------------------------------------------------
# File content generators
# ---------------------------------------------------------------------------

def _generate_tfvars(
    env_name: str,
    grafana_url: str,
    vault_addr: str,
    vault_mount: str,
    vault_namespace: str,
    keycloak_url: str,
) -> str:
    upper = env_name.upper()
    vault_ns_line = (
        f'vault_namespace = "{vault_namespace}"'
        if vault_namespace
        else '# vault_namespace = "admin/grafana"   # e.g., admin/team-x'
    )
    keycloak_line = (
        f'keycloak_url = "{keycloak_url}"'
        if keycloak_url
        else '# keycloak_url = "https://keycloak.example.com"'
    )
    return (
        f"# =============================================================================\n"
        f"# {upper} ENVIRONMENT \u2014 Terraform Variables\n"
        f"# =============================================================================\n"
        f"# This file contains all Terraform variables for the '{env_name}' environment.\n"
        f"#\n"
        f"# Usage:\n"
        f"#   make plan  ENV={env_name}\n"
        f"#   make apply ENV={env_name}\n"
        f"#\n"
        f"# Or directly:\n"
        f"#   terraform plan  -var-file=envs/{env_name}/terraform.tfvars\n"
        f"#   terraform apply -var-file=envs/{env_name}/terraform.tfvars\n"
        f"# =============================================================================\n"
        f"\n"
        f"# \u2500\u2500\u2500 Grafana Connection \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n"
        f"# The full URL of your Grafana instance (including protocol and port)\n"
        f'grafana_url = "{grafana_url}"\n'
        f"\n"
        f"# Environment name \u2014 used to locate envs/ subdirectory\n"
        f"# Must match: envs/{env_name}/ and envs/{env_name}/dashboards/\n"
        f'environment = "{env_name}"\n'
        f"\n"
        f"# \u2500\u2500\u2500 Vault Configuration \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n"
        f"# HashiCorp Vault for secrets management (datasource passwords, SSO secrets)\n"
        f'vault_address = "{vault_addr}"\n'
        f'vault_mount   = "{vault_mount}"\n'
        f"\n"
        f"# Vault Enterprise namespace (leave commented for OSS Vault or root namespace)\n"
        f"# See: https://developer.hashicorp.com/vault/docs/enterprise/namespaces\n"
        f"{vault_ns_line}\n"
        f"\n"
        f"# \u2500\u2500\u2500 Vault Secret Paths \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n"
        f"# Path prefixes within the vault_mount for each resource type.\n"
        f"# Defaults match the layout written by import_from_grafana.py.\n"
        f"# Uncomment and change ONLY if your Vault topology differs.\n"
        f"#\n"
        f'# vault_path_grafana_auth      = "grafana/auth"\n'
        f'# vault_path_datasources        = "grafana/datasources"\n'
        f'# vault_path_contact_points     = "grafana/alerting/contact-points"\n'
        f'# vault_path_sso                = "grafana/sso/keycloak"\n'
        f'# vault_path_keycloak           = "grafana/keycloak/client"\n'
        f'# vault_path_service_accounts   = "grafana/service-accounts"\n'
        f"\n"
        f"# The vault token should be set via environment variable for security:\n"
        f'#   export VAULT_TOKEN="your-vault-token"\n'
        f"#\n"
        f"# To set up secrets in Vault:\n"
        f"#   make vault-setup ENV={env_name}\n"
        f"\n"
        f"# \u2500\u2500\u2500 Keycloak (Optional) \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n"
        f"# Only needed if you enable SSO via Keycloak (see envs/{env_name}/sso.yaml)\n"
        f"{keycloak_line}\n"
        f"\n"
        f"# \u2500\u2500\u2500 Additional Variables \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n"
        f"# Uncomment and set any additional variables your Terraform config needs:\n"
        f"#\n"
        f"# # Grafana authentication (alternative to Vault-stored API key)\n"
        f'# # grafana_auth = "admin:admin"          # Only for local dev!\n'
        f"#\n"
        f"# # Terraform state locking timeout\n"
        f'# # lock_timeout = "5m"\n'
        f"#\n"
        f"# # Enable/disable specific resource categories\n"
        f"# # manage_dashboards      = true\n"
        f"# # manage_datasources     = true\n"
        f"# # manage_alerting        = true\n"
        f"# # manage_service_accounts = true\n"
    )


def _generate_backend(env_name: str, backend: str) -> str:
    s3 = "" if backend == "s3" else "#"
    azure = "" if backend == "azurerm" else "#"
    gcs = "" if backend == "gcs" else "#"
    gitlab = "" if backend == "gitlab" else "#"
    return (
        f"# =============================================================================\n"
        f"# BACKEND CONFIGURATION \u2014 {env_name}\n"
        f"# =============================================================================\n"
        f"# Remote state backends store terraform.tfstate on a shared backend\n"
        f"# instead of the local filesystem, enabling team collaboration.\n"
        f"#\n"
        f"# Usage:\n"
        f"#   make init ENV={env_name}\n"
        f"# Or:\n"
        f"#   terraform init -backend-config=envs/{env_name}/backend.tfbackend\n"
        f"#\n"
        f"# Uncomment ONE backend section below (or use BACKEND= when creating the env).\n"
        f"# For local-only state, you can leave everything commented.\n"
        f"# =============================================================================\n"
        f"\n"
        f'# --- AWS S3 Backend ---\n'
        f'# Prerequisites: S3 bucket + DynamoDB table for state locking\n'
        f'# See: https://developer.hashicorp.com/terraform/language/backend/s3\n'
        f'{s3} bucket         = "my-terraform-state"\n'
        f'{s3} key            = "{env_name}/grafana/terraform.tfstate"\n'
        f'{s3} region         = "us-east-1"\n'
        f'{s3} encrypt        = true\n'
        f'{s3} dynamodb_table = "terraform-locks"\n'
        f"\n"
        f'# --- Azure Blob Storage ---\n'
        f'# Prerequisites: Storage account + container\n'
        f'# See: https://developer.hashicorp.com/terraform/language/backend/azurerm\n'
        f'{azure} resource_group_name  = "my-rg"\n'
        f'{azure} storage_account_name = "mytfstate"\n'
        f'{azure} container_name       = "tfstate"\n'
        f'{azure} key                  = "{env_name}/grafana/terraform.tfstate"\n'
        f"\n"
        f'# --- Google Cloud Storage ---\n'
        f'# Prerequisites: GCS bucket with versioning enabled\n'
        f'# See: https://developer.hashicorp.com/terraform/language/backend/gcs\n'
        f'{gcs} bucket = "my-terraform-state"\n'
        f'{gcs} prefix = "{env_name}/grafana"\n'
        f"\n"
        f'# --- GitLab HTTP Backend ---\n'
        f'# Prerequisites: GitLab project with Terraform state enabled\n'
        f'# Auth: set TF_HTTP_USERNAME and TF_HTTP_PASSWORD env vars\n'
        f'#   export TF_HTTP_USERNAME="gitlab-ci-token"  # or your username\n'
        f'#   export TF_HTTP_PASSWORD="${{CI_JOB_TOKEN}}"   # or a personal access token\n'
        f'# See: https://docs.gitlab.com/ee/user/infrastructure/iac/terraform_state.html\n'
        f'{gitlab} address        = "https://gitlab.example.com/api/v4/projects/<PROJECT_ID>/terraform/state/{env_name}"\n'
        f'{gitlab} lock_address   = "https://gitlab.example.com/api/v4/projects/<PROJECT_ID>/terraform/state/{env_name}/lock"\n'
        f'{gitlab} unlock_address = "https://gitlab.example.com/api/v4/projects/<PROJECT_ID>/terraform/state/{env_name}/lock"\n'
        f'{gitlab} lock_method    = "POST"\n'
        f'{gitlab} unlock_method  = "DELETE"\n'
        f'{gitlab} retry_wait_min = 5\n'
    )


def _generate_organizations(env_name: str) -> str:
    upper = env_name.upper()
    cap = env_name.capitalize()
    return (
        f"# =============================================================================\n"
        f"# {upper} \u2014 Organization Overrides\n"
        f"# =============================================================================\n"
        f"# Override shared organization settings for THIS environment only.\n"
        f"# Matching is by organization \"name\" \u2014 shared entries with the same name\n"
        f"# are replaced by entries here.\n"
        f"#\n"
        f"# Tip: Organizations are usually identical across environments.\n"
        f"#      Only add overrides here if {env_name} needs different admins/editors.\n"
        f"# =============================================================================\n"
        f"\n"
        f"organizations: []\n"
        f"\n"
        f'  # --- Example: Override org admins for this environment ---\n'
        f'  # - name: "Main Organization"\n'
        f'  #   id: 1\n'
        f'  #   admins:\n'
        f'  #     - "admin-{env_name}@example.com"\n'
        f'  #   editors:\n'
        f'  #     - "dev-{env_name}@example.com"\n'
        f'  #   viewers: []\n'
        f'  #\n'
        f'  # --- Example: Add an env-specific organization ---\n'
        f'  # - name: "{cap} QA Team"\n'
        f'  #   admins:\n'
        f'  #     - "qa-lead@example.com"\n'
    )


def _generate_datasources(env_name: str, vault_mount: str, datasources_str: str) -> str:
    upper = env_name.upper()
    header = (
        f"# =============================================================================\n"
        f"# {upper} \u2014 Datasource Overrides\n"
        f"# =============================================================================\n"
        f"# Override shared datasource settings for THIS environment only.\n"
        f"# Matching is by datasource \"uid\" \u2014 shared entries with the same UID\n"
        f"# are replaced by entries here.\n"
        f"#\n"
        f"# Common use case: same datasource type, different URL per environment.\n"
        f"#\n"
        f"# For secrets (passwords, tokens), set use_vault: true and store credentials\n"
        f"# in Vault at: {vault_mount}/{env_name}/datasources/<datasource-name>\n"
        f"# =============================================================================\n"
        f"\n"
    )

    if not datasources_str:
        return header + (
            f"datasources: []\n"
            f"\n"
            f'  # --- Example: Override Prometheus URL for this environment ---\n'
            f'  # - name: "Prometheus"\n'
            f'  #   type: "prometheus"\n'
            f'  #   uid: "prometheus"                    # Must match the shared UID to override\n'
            f'  #   url: "http://prometheus-{env_name}:9090"\n'
            f'  #   org: "Main Organization"\n'
            f'  #   is_default: true\n'
            f'  #   access_mode: "proxy"\n'
            f'  #   json_data:\n'
            f'  #     httpMethod: "POST"\n'
            f'  #     timeInterval: "15s"\n'
            f'  #\n'
            f'  # --- Example: Loki with environment-specific URL ---\n'
            f'  # - name: "Loki"\n'
            f'  #   type: "loki"\n'
            f'  #   uid: "loki"\n'
            f'  #   url: "http://loki-{env_name}:3100"\n'
            f'  #   org: "Main Organization"\n'
            f'  #   json_data:\n'
            f'  #     maxLines: 1000\n'
            f'  #\n'
            f'  # --- Example: PostgreSQL with Vault credentials ---\n'
            f'  # - name: "PostgreSQL"\n'
            f'  #   type: "grafana-postgresql-datasource"\n'
            f'  #   uid: "postgres"\n'
            f'  #   url: "postgres-{env_name}.example.com:5432"\n'
            f'  #   org: "Main Organization"\n'
            f'  #   use_vault: true                      # Reads from: {vault_mount}/{env_name}/datasources/PostgreSQL\n'
            f'  #   json_data:\n'
            f'  #     database: "grafana_{env_name}"\n'
            f'  #     sslmode: "require"\n'
            f'  #     maxOpenConns: 10\n'
            f'  #\n'
            f'  # --- Example: Elasticsearch ---\n'
            f'  # - name: "Elasticsearch"\n'
            f'  #   type: "elasticsearch"\n'
            f'  #   uid: "elasticsearch"\n'
            f'  #   url: "http://elasticsearch-{env_name}:9200"\n'
            f'  #   org: "Main Organization"\n'
            f'  #   json_data:\n'
            f'  #     esVersion: "8.0.0"\n'
            f'  #     timeField: "@timestamp"\n'
            f'  #     logMessageField: "message"\n'
            f'  #     logLevelField: "level"\n'
        )

    parts: list[str] = ["datasources:\n"]
    ds_list = [d.strip() for d in datasources_str.split(",") if d.strip()]
    first = True
    for ds in ds_list:
        is_default = "true" if first else "false"
        first = False
        if ds == "prometheus":
            parts.append(
                f'  - name: "Prometheus"\n'
                f'    type: "prometheus"\n'
                f'    uid: "prometheus"\n'
                f'    url: "http://prometheus-{env_name}:9090"\n'
                f'    org: "Main Organization"\n'
                f'    is_default: {is_default}\n'
                f'    json_data:\n'
                f'      httpMethod: "POST"\n'
                f'      timeInterval: "15s"\n'
            )
        elif ds == "loki":
            parts.append(
                f'  - name: "Loki"\n'
                f'    type: "loki"\n'
                f'    uid: "loki"\n'
                f'    url: "http://loki-{env_name}:3100"\n'
                f'    org: "Main Organization"\n'
                f'    json_data:\n'
                f'      maxLines: 1000\n'
            )
        elif ds in ("postgres", "postgresql"):
            parts.append(
                f'  - name: "PostgreSQL"\n'
                f'    type: "postgres"\n'
                f'    uid: "postgres"\n'
                f'    url: "postgres-{env_name}.example.com:5432"\n'
                f'    org: "Main Organization"\n'
                f'    use_vault: true\n'
                f'    json_data:\n'
                f'      database: "grafana_{env_name}"\n'
                f'      sslmode: "require"\n'
                f'      maxOpenConns: 10\n'
            )
        elif ds == "mysql":
            parts.append(
                f'  - name: "MySQL"\n'
                f'    type: "mysql"\n'
                f'    uid: "mysql"\n'
                f'    url: "mysql-{env_name}.example.com:3306"\n'
                f'    org: "Main Organization"\n'
                f'    use_vault: true\n'
                f'    json_data:\n'
                f'      database: "grafana_{env_name}"\n'
                f'      maxOpenConns: 10\n'
            )
        elif ds in ("elasticsearch", "elastic"):
            parts.append(
                f'  - name: "Elasticsearch"\n'
                f'    type: "elasticsearch"\n'
                f'    uid: "elasticsearch"\n'
                f'    url: "http://elasticsearch-{env_name}:9200"\n'
                f'    org: "Main Organization"\n'
                f'    json_data:\n'
                f'      esVersion: "8.0.0"\n'
                f'      timeField: "@timestamp"\n'
                f'      logMessageField: "message"\n'
                f'      logLevelField: "level"\n'
            )
        elif ds in ("influxdb", "influx"):
            parts.append(
                f'  - name: "InfluxDB"\n'
                f'    type: "influxdb"\n'
                f'    uid: "influxdb"\n'
                f'    url: "http://influxdb-{env_name}:8086"\n'
                f'    org: "Main Organization"\n'
                f'    use_vault: true\n'
                f'    json_data:\n'
                f'      version: "Flux"\n'
                f'      organization: "my-org"\n'
                f'      defaultBucket: "my-bucket"\n'
            )
        elif ds == "tempo":
            parts.append(
                f'  - name: "Tempo"\n'
                f'    type: "tempo"\n'
                f'    uid: "tempo"\n'
                f'    url: "http://tempo-{env_name}:3200"\n'
                f'    org: "Main Organization"\n'
                f'    json_data:\n'
                f'      tracesToLogsV2:\n'
                f'        datasourceUid: "loki"\n'
                f'      tracesToMetrics:\n'
                f'        datasourceUid: "prometheus"\n'
            )
        elif ds == "mimir":
            parts.append(
                f'  - name: "Mimir"\n'
                f'    type: "prometheus"\n'
                f'    uid: "mimir"\n'
                f'    url: "http://mimir-{env_name}:9009/prometheus"\n'
                f'    org: "Main Organization"\n'
                f'    json_data:\n'
                f'      httpMethod: "POST"\n'
            )
        elif ds == "cloudwatch":
            parts.append(
                f'  - name: "CloudWatch"\n'
                f'    type: "cloudwatch"\n'
                f'    uid: "cloudwatch"\n'
                f'    org: "Main Organization"\n'
                f'    json_data:\n'
                f'      defaultRegion: "us-east-1"\n'
                f'      authType: "default"\n'
            )
        elif ds == "graphite":
            parts.append(
                f'  - name: "Graphite"\n'
                f'    type: "graphite"\n'
                f'    uid: "graphite"\n'
                f'    url: "http://graphite-{env_name}:8080"\n'
                f'    org: "Main Organization"\n'
                f'    json_data:\n'
                f'      graphiteVersion: "1.1"\n'
            )
        else:
            parts.append(f'  # Unknown datasource type: {ds} \u2014 add manually\n')

    return header + "".join(parts)


def _generate_folders(env_name: str) -> str:
    upper = env_name.upper()
    return (
        f"# =============================================================================\n"
        f"# {upper} \u2014 Folder Permission Overrides\n"
        f"# =============================================================================\n"
        f"# Folders are auto-discovered from the dashboards/ directory structure:\n"
        f"#   envs/{env_name}/dashboards/<org_name>/<folder_uid>/\n"
        f"#   base/dashboards/<org_name>/<folder_uid>/\n"
        f"#\n"
        f"# This file is ONLY for setting permissions on those folders.\n"
        f"# If a folder is not listed here, it gets default (org-level) permissions.\n"
        f"# =============================================================================\n"
        f"\n"
        f"folders: []\n"
        f"\n"
        f'  # --- Example: Restrict folder access to specific teams ---\n'
        f'  # - uid: "infrastructure"               # Must match the directory name\n'
        f'  #   name: "Infrastructure Monitoring"    # Display name in Grafana\n'
        f'  #   org: "Main Organization"\n'
        f'  #   permissions:\n'
        f'  #     - team: "SRE Team"\n'
        f'  #       permission: "Admin"              # Admin | Edit | View\n'
        f'  #     - team: "Backend Team"\n'
        f'  #       permission: "Edit"\n'
        f'  #     - role: "Viewer"                   # Built-in role\n'
        f'  #       permission: "View"\n'
        f'  #\n'
        f'  # --- Example: Editor-accessible folder ---\n'
        f'  # - uid: "applications"\n'
        f'  #   name: "Application Dashboards"\n'
        f'  #   org: "Main Organization"\n'
        f'  #   permissions:\n'
        f'  #     - role: "Editor"\n'
        f'  #       permission: "Edit"\n'
        f'  #     - role: "Viewer"\n'
        f'  #       permission: "View"\n'
    )


def _generate_teams(env_name: str) -> str:
    upper = env_name.upper()
    cap = env_name.capitalize()
    return (
        f"# =============================================================================\n"
        f"# {upper} \u2014 Team Overrides\n"
        f"# =============================================================================\n"
        f"# Override shared team settings for THIS environment only.\n"
        f"# Matching is by team \"name\" \u2014 shared entries with the same name\n"
        f"# are replaced by entries here.\n"
        f"#\n"
        f"# Teams are organization-scoped. Each team must specify \"org\".\n"
        f"# Teams can be assigned folder permissions (see folders.yaml).\n"
        f"# =============================================================================\n"
        f"\n"
        f"teams: []\n"
        f"\n"
        f'  # --- Example: Override team members for this environment ---\n'
        f'  # - name: "Backend Team"\n'
        f'  #   org: "Main Organization"\n'
        f'  #   email: "backend-{env_name}@example.com"\n'
        f'  #   members:\n'
        f'  #     - "dev1@example.com"\n'
        f'  #     - "dev2@example.com"\n'
        f'  #   preferences:\n'
        f'  #     theme: "dark"\n'
        f'  #     # home_dashboard_uid: "my-dashboard"\n'
        f'  #\n'
        f'  # --- Example: Environment-specific team ---\n'
        f'  # - name: "{cap} On-Call"\n'
        f'  #   org: "Main Organization"\n'
        f'  #   email: "oncall-{env_name}@example.com"\n'
        f'  #   preferences:\n'
        f'  #     theme: "dark"\n'
    )


def _generate_service_accounts(env_name: str) -> str:
    upper = env_name.upper()
    return (
        f"# =============================================================================\n"
        f"# {upper} \u2014 Service Account Overrides\n"
        f"# =============================================================================\n"
        f"# Override shared service account settings for THIS environment only.\n"
        f"# Matching is by account \"name\" \u2014 shared entries with the same name\n"
        f"# are replaced by entries here.\n"
        f"#\n"
        f"# Service accounts provide programmatic access to Grafana via API tokens.\n"
        f"# Tokens are auto-generated and stored in Terraform state (sensitive).\n"
        f"# =============================================================================\n"
        f"\n"
        f"service_accounts: []\n"
        f"\n"
        f'  # --- Example: Automation service account for this environment ---\n'
        f'  # - name: "terraform-{env_name}"\n'
        f'  #   org: "Main Organization"\n'
        f'  #   role: "Admin"                        # Admin | Editor | Viewer\n'
        f'  #   is_disabled: false\n'
        f'  #   tokens:\n'
        f'  #     - name: "main-token"\n'
        f'  #       seconds_to_live: 0               # 0 = never expires\n'
        f'  #\n'
        f'  # --- Example: Read-only CI/CD account ---\n'
        f'  # - name: "ci-cd-readonly"\n'
        f'  #   org: "Main Organization"\n'
        f'  #   role: "Viewer"\n'
        f'  #   tokens:\n'
        f'  #     - name: "pipeline-token"\n'
        f'  #       seconds_to_live: 31536000        # 1 year in seconds\n'
    )


def _generate_sso(env_name: str, vault_mount: str, keycloak_url: str) -> str:
    upper = env_name.upper()
    header = (
        f"# =============================================================================\n"
        f"# {upper} \u2014 SSO Configuration Overrides\n"
        f"# =============================================================================\n"
        f"# Override shared SSO settings for THIS environment only.\n"
        f"# Values here are merged with base/sso.yaml.\n"
        f"#\n"
        f"# Supported providers: Keycloak, Okta, Azure AD, Google, GitHub\n"
        f"# Client secrets are fetched from Vault at: {vault_mount}/{env_name}/sso/keycloak\n"
        f"#\n"
        f"# Key features:\n"
        f"#   - allowed_groups: restrict login to specific IdP groups\n"
        f"#   - groups[].org_mappings: map IdP groups to Grafana orgs + roles\n"
        f"#   - team sync: sync IdP groups to Grafana teams\n"
        f"# =============================================================================\n"
        f"\n"
    )
    if keycloak_url:
        body = (
            f"sso:\n"
            f'  enabled: true\n'
            f'  name: "Keycloak"\n'
            f"\n"
            f"  # \u2500\u2500\u2500 OAuth2 Endpoints \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n"
            f'  auth_url: "{keycloak_url}/realms/grafana/protocol/openid-connect/auth"\n'
            f'  token_url: "{keycloak_url}/realms/grafana/protocol/openid-connect/token"\n'
            f'  api_url: "{keycloak_url}/realms/grafana/protocol/openid-connect/userinfo"\n'
            f"\n"
            f"  # \u2500\u2500\u2500 Client Configuration \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n"
            f'  # client_id: "grafana-{env_name}"\n'
            f"  # use_vault: true                        # client_secret from Vault\n"
            f"\n"
            f"  # \u2500\u2500\u2500 OAuth Settings \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n"
            f"  allow_sign_up: true\n"
            f"  auto_login: false\n"
            f'  scopes: "openid profile email groups"\n'
            f"  use_pkce: true\n"
            f"  use_refresh_token: true\n"
            f"\n"
            f"  # \u2500\u2500\u2500 Access Control: Allowed Groups \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n"
            f"  # Restrict login to ONLY users in these IdP groups (comma-separated).\n"
            f"  # Users NOT in any of these groups will be denied access entirely.\n"
            f"  # Leave empty or remove to allow all authenticated users.\n"
            f'  # allowed_groups: "grafana-admins,grafana-editors,grafana-viewers"\n'
            f"\n"
            f"  # \u2500\u2500\u2500 Role Mapping \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n"
            f"  # skip_org_role_sync: false              # true = roles come ONLY from groups below\n"
            f"  # allow_assign_grafana_admin: true       # Allow granting server-wide admin via groups\n"
            f"\n"
            f"  # \u2500\u2500\u2500 Sign Out \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n"
            f'  # signout_redirect_url: "{keycloak_url}/realms/grafana/protocol/openid-connect/logout"\n'
            f"\n"
            f"  # \u2500\u2500\u2500 Team Sync \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n"
            f"  # Sync IdP groups to Grafana teams automatically\n"
            f'  # teams_url: "{keycloak_url}/realms/grafana/protocol/openid-connect/userinfo"\n'
            f'  # team_ids_attribute_path: "groups[*]"\n'
            f"\n"
            f"  # \u2500\u2500\u2500 Group to Org Role Mappings \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n"
            f"  # Maps IdP groups to Grafana organizations with specific roles.\n"
            f"  # Users ONLY get access to orgs explicitly listed in their group's org_mappings.\n"
            f"  #\n"
            f"  # Roles: Admin, Editor, Viewer (for org access)\n"
            f"  # Special: if a group has Admin on all orgs + allow_assign_grafana_admin: true,\n"
            f"  #          members get server-wide super admin rights.\n"
            f"  #\n"
            f"  # groups:\n"
            f'  #   - name: "grafana-admins"\n'
            f"  #     org_mappings:\n"
            f'  #       - org: "Main Organization"\n'
            f'  #         role: "Admin"\n'
            f'  #       - org: "Platform Team"\n'
            f'  #         role: "Admin"\n'
            f"  #\n"
            f'  #   - name: "grafana-editors"\n'
            f"  #     org_mappings:\n"
            f'  #       - org: "Main Organization"\n'
            f'  #         role: "Editor"\n'
            f"  #\n"
            f'  #   - name: "grafana-viewers"\n'
            f"  #     org_mappings:\n"
            f'  #       - org: "Main Organization"\n'
            f'  #         role: "Viewer"\n'
        )
    else:
        body = (
            f"sso: {{}}\n"
            f"\n"
            f'  # --- Example: Keycloak SSO for this environment ---\n'
            f'  # enabled: true\n'
            f'  # name: "Keycloak"\n'
            f"  #\n"
            f"  # # OAuth2 endpoints\n"
            f'  # auth_url: "https://keycloak-{env_name}.example.com/realms/grafana/protocol/openid-connect/auth"\n'
            f'  # token_url: "https://keycloak-{env_name}.example.com/realms/grafana/protocol/openid-connect/token"\n'
            f'  # api_url: "https://keycloak-{env_name}.example.com/realms/grafana/protocol/openid-connect/userinfo"\n'
            f'  # client_id: "grafana-{env_name}"\n'
            f"  # use_vault: true                        # Reads from: {vault_mount}/{env_name}/sso/keycloak\n"
            f"  #\n"
            f"  # # OAuth settings\n"
            f"  # allow_sign_up: true\n"
            f"  # auto_login: false\n"
            f'  # scopes: "openid profile email groups"\n'
            f"  # use_pkce: true\n"
            f"  # use_refresh_token: true\n"
            f"  #\n"
            f"  # # Restrict login to specific IdP groups (comma-separated)\n"
            f"  # # Users NOT in any of these groups will be denied access entirely\n"
            f'  # allowed_groups: "grafana-admins,grafana-editors,grafana-viewers"\n'
            f"  #\n"
            f"  # # Role mapping\n"
            f"  # skip_org_role_sync: false              # true = roles come ONLY from groups below\n"
            f"  # allow_assign_grafana_admin: true       # Allow granting server-wide admin\n"
            f"  #\n"
            f"  # # Sign out redirect (back to IdP logout)\n"
            f'  # signout_redirect_url: "https://keycloak-{env_name}.example.com/realms/grafana/protocol/openid-connect/logout"\n'
            f"  #\n"
            f"  # # Team sync \u2014 sync IdP groups to Grafana teams\n"
            f'  # teams_url: "https://keycloak-{env_name}.example.com/realms/grafana/protocol/openid-connect/userinfo"\n'
            f'  # team_ids_attribute_path: "groups[*]"\n'
            f"  #\n"
            f"  # # Map IdP groups \u2192 Grafana orgs + roles\n"
            f"  # # Users ONLY get access to orgs listed in their group's mappings\n"
            f"  # groups:\n"
            f'  #   - name: "grafana-admins"\n'
            f"  #     org_mappings:\n"
            f'  #       - org: "Main Organization"\n'
            f'  #         role: "Admin"\n'
            f'  #       - org: "Platform Team"\n'
            f'  #         role: "Admin"\n'
            f"  #\n"
            f'  #   - name: "grafana-editors"\n'
            f"  #     org_mappings:\n"
            f'  #       - org: "Main Organization"\n'
            f'  #         role: "Editor"\n'
            f"  #\n"
            f'  #   - name: "grafana-viewers"\n'
            f"  #     org_mappings:\n"
            f'  #       - org: "Main Organization"\n'
            f'  #         role: "Viewer"\n'
            f"  #\n"
            f"  # --- Example: Azure AD SSO ---\n"
            f"  # enabled: true\n"
            f'  # name: "Azure AD"\n'
            f'  # auth_url: "https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/authorize"\n'
            f'  # token_url: "https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token"\n'
            f'  # client_id: "grafana-{env_name}"\n'
            f"  # use_vault: true\n"
            f'  # scopes: "openid profile email"\n'
        )
    return header + body


def _generate_keycloak(env_name: str, vault_mount: str, keycloak_url: str) -> str:
    upper = env_name.upper()
    cap = env_name.capitalize()
    header = (
        f"# =============================================================================\n"
        f"# {upper} \u2014 Keycloak Client Management (Optional)\n"
        f"# =============================================================================\n"
        f"# Set enabled: true to let Terraform manage a Keycloak OAuth client\n"
        f"# for Grafana. This is SEPARATE from SSO \u2014 SSO can use any provider,\n"
        f"# while this manages the Keycloak client configuration itself.\n"
        f"#\n"
        f"# Credentials from Vault at: {vault_mount}/{env_name}/keycloak/provider-auth\n"
        f"# =============================================================================\n"
        f"\n"
    )
    if keycloak_url:
        body = (
            f"keycloak:\n"
            f"  enabled: true\n"
            f'  url: "{keycloak_url}"\n'
            f'  realm: "grafana"\n'
            f'  # client_id: "grafana-{env_name}"\n'
            f'  # client_name: "Grafana {cap} (Terraform Managed)"\n'
            f'  # description: "Grafana OAuth Client for {env_name}"\n'
            f"  #\n"
            f"  # --- OAuth Settings ---\n"
            f'  # access_type: "CONFIDENTIAL"           # CONFIDENTIAL | PUBLIC\n'
            f"  # standard_flow_enabled: true\n"
            f"  # valid_redirect_uris:\n"
            f'  #   - "https://grafana-{env_name}.example.com/login/generic_oauth"\n'
            f"  # web_origins:\n"
            f'  #   - "https://grafana-{env_name}.example.com"\n'
        )
    else:
        body = (
            f"keycloak: {{}}\n"
            f"\n"
            f"  # --- Example: Manage Keycloak client via Terraform ---\n"
            f"  # enabled: true\n"
            f'  # url: "https://keycloak.example.com"\n'
            f'  # realm: "grafana"\n'
            f'  # client_id: "grafana-{env_name}"\n'
            f'  # client_name: "Grafana {cap}"\n'
            f"  #\n"
            f'  # access_type: "CONFIDENTIAL"\n'
            f"  # standard_flow_enabled: true\n"
            f"  # valid_redirect_uris:\n"
            f'  #   - "https://grafana-{env_name}.example.com/login/generic_oauth"\n'
            f"  # web_origins:\n"
            f'  #   - "https://grafana-{env_name}.example.com"\n'
        )
    return header + body


# Templates for files that contain Grafana/Jinja2 {{ }} syntax in comments.
# Using @@ENV@@ / @@UPPER@@ placeholders to avoid Python f-string escaping.

_ALERT_RULES_TMPL = """\
# =============================================================================
# @@UPPER@@ \u2014 Alert Rule Overrides
# =============================================================================
# Override shared alert rules for THIS environment only.
# Matching is by folder + rule group name.
#
# Each group must specify:
#   - folder: the folder UID (must match a directory in dashboards/ or an entry in folders.yaml)
#   - name: rule group name
#   - interval: evaluation interval (e.g., "1m", "5m")
#   - org: which organization this alert belongs to
#   - rules: list of alert rules
# =============================================================================

groups: []

  # --- Example: Environment-specific alert thresholds ---
  # - folder: "alerts"                    # Must exist in envs/@@ENV@@/dashboards/
  #   name: "High CPU Usage"
  #   interval: "1m"
  #   org: "Main Organization"
  #   rules:
  #     - title: "CPU Usage Critical"
  #       condition: "C"
  #       for: "5m"
  #       annotations:
  #         summary: "CPU usage is above 90% on @@ENV@@"
  #         description: "Instance {{ $labels.instance }} has CPU > 90%"
  #       labels:
  #         severity: "critical"
  #         environment: "@@ENV@@"
  #       noDataState: "NoData"           # NoData | Alerting | OK
  #       execErrState: "Error"           # Error | Alerting | OK
  #       data:
  #         - refId: "A"
  #           datasourceUid: "prometheus"
  #           model:
  #             expr: "100 - (avg by(instance) (rate(node_cpu_seconds_total{mode=\\"idle\\"}[5m])) * 100)"
  #         - refId: "C"
  #           datasourceUid: "-100"       # __expr__ (expression)
  #           model:
  #             type: "threshold"
  #             conditions:
  #               - evaluator:
  #                   type: "gt"
  #                   params: [90]         # Alert when > 90%
"""

_CONTACT_POINTS_TMPL = """\
# =============================================================================
# @@UPPER@@ \u2014 Contact Point Overrides
# =============================================================================
# Override shared contact points for THIS environment only.
# Matching is by contact point "name".
#
# Supported receiver types: email, webhook, slack, pagerduty, opsgenie,
#   discord, telegram, teams, googlechat, victorops, pushover, sns,
#   sensugo, threema, webex, line, kafka, oncall, alertmanager
# =============================================================================

contactPoints: []

  # --- Example: Email alerts for this environment ---
  # - name: "@@ENV@@-email-alerts"
  #   org: "Main Organization"
  #   receivers:
  #     - type: "email"
  #       settings:
  #         addresses: "oncall-@@ENV@@\u0040example.com;team\u0040example.com"
  #         singleEmail: false
  #
  # --- Example: Slack channel per environment ---
  # - name: "@@ENV@@-slack"
  #   org: "Main Organization"
  #   receivers:
  #     - type: "slack"
  #       settings:
  #         url: "https://hooks.slack.com/services/xxx/yyy/zzz"
  #         recipient: "#alerts-@@ENV@@"
  #         username: "Grafana @@CAP@@"
  #         icon_emoji: ":grafana:"
  #         title: '{{ template "slack.default.title" . }}'
  #         text: '{{ template "slack.default.text" . }}'
  #
  # --- Example: PagerDuty ---
  # - name: "@@ENV@@-pagerduty"
  #   org: "Main Organization"
  #   receivers:
  #     - type: "pagerduty"
  #       settings:
  #         integrationKey: "your-pagerduty-key"  # Store in Vault for security
  #         severity: "critical"
  #         class: "grafana"
  #
  # --- Example: Webhook (generic HTTP endpoint) ---
  # - name: "@@ENV@@-webhook"
  #   org: "Main Organization"
  #   receivers:
  #     - type: "webhook"
  #       settings:
  #         url: "https://alerts-@@ENV@@.example.com/webhook"
  #         httpMethod: "POST"
  #         username: "grafana"
  #         # password from Vault: use_vault: true
"""

_NOTIFICATION_POLICIES_TMPL = """\
# =============================================================================
# @@UPPER@@ \u2014 Notification Policy Overrides
# =============================================================================
# Override shared notification policies for THIS environment only.
# Matching is by organization.
#
# Policies define HOW alerts are routed to contact points:
#   - receiver: the default contact point
#   - group_by: labels to group alerts by
#   - routes: child policies with label matchers
# =============================================================================

policies: []

  # --- Example: Route alerts by severity ---
  # - org: "Main Organization"
  #   receiver: "@@ENV@@-email-alerts"     # Default contact point
  #   group_by:
  #     - "alertname"
  #     - "namespace"
  #   group_wait: "30s"
  #   group_interval: "5m"
  #   repeat_interval: "4h"
  #   routes:
  #     # Critical alerts \u2192 PagerDuty
  #     - receiver: "@@ENV@@-pagerduty"
  #       matchers:
  #         - "severity = critical"
  #       continue: false
  #       group_wait: "10s"                    # Alert faster for critical
  #
  #     # Warning alerts \u2192 Slack
  #     - receiver: "@@ENV@@-slack"
  #       matchers:
  #         - "severity = warning"
  #       continue: true                       # Also send to default receiver
  #       repeat_interval: "1h"
  #
  #     # Mute notifications for specific labels
  #     # - receiver: "@@ENV@@-email-alerts"
  #     #   matchers:
  #     #     - "alertname = Watchdog"
  #     #   mute_time_intervals:
  #     #     - "weekends"
"""


def _generate_alert_rules(env_name: str) -> str:
    return _fill(_ALERT_RULES_TMPL, ENV=env_name, UPPER=env_name.upper())


def _generate_contact_points(env_name: str) -> str:
    return _fill(
        _CONTACT_POINTS_TMPL,
        ENV=env_name,
        UPPER=env_name.upper(),
        CAP=env_name.capitalize(),
    )


def _generate_notification_policies(env_name: str) -> str:
    return _fill(_NOTIFICATION_POLICIES_TMPL, ENV=env_name, UPPER=env_name.upper())


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:  # noqa: C901
    parser = argparse.ArgumentParser(
        description="Create all files needed for a new Grafana-as-Code environment",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  %(prog)s staging\n"
            "  %(prog)s prod --grafana-url=https://grafana.example.com --backend=s3\n"
            "  %(prog)s dev --datasources=prometheus,loki,postgres\n"
            "  %(prog)s test --orgs='Main Organization,Platform Team,BI'\n"
            "\n"
            "Via Make:\n"
            "  make new-env NAME=staging\n"
            "  make new-env NAME=prod GRAFANA_URL=https://grafana.example.com BACKEND=s3\n"
        ),
    )
    parser.add_argument(
        "env_name",
        nargs="?",
        default="",
        help="Environment name (must start with a letter)",
    )
    parser.add_argument("--name", dest="name_flag", default="", help=argparse.SUPPRESS)
    parser.add_argument(
        "--grafana-url",
        default="",
        help="Grafana URL (default: http://localhost:3000)",
    )
    parser.add_argument(
        "--vault-addr",
        default="",
        help="Vault address (default: http://localhost:8200)",
    )
    parser.add_argument(
        "--vault-mount",
        default="",
        help="Vault KV mount path (default: grafana)",
    )
    parser.add_argument(
        "--vault-namespace",
        default="",
        help="Vault Enterprise namespace",
    )
    parser.add_argument(
        "--keycloak-url",
        default="",
        help="Keycloak URL (enables SSO configuration)",
    )
    parser.add_argument(
        "--backend",
        default="",
        choices=["", "s3", "azurerm", "gcs", "gitlab"],
        help="Remote state backend type",
    )
    parser.add_argument(
        "--orgs",
        default="",
        help="Comma-separated organization names",
    )
    parser.add_argument(
        "--datasources",
        default="",
        help=(
            "Comma-separated datasource presets: "
            "prometheus, loki, postgres, mysql, elasticsearch, "
            "influxdb, tempo, mimir, cloudwatch, graphite"
        ),
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be created without writing files",
    )
    args = parser.parse_args()

    # Resolve env_name (positional > --name flag > ENV_NAME_ARG env var)
    env_name: str = args.env_name or args.name_flag or os.environ.get("ENV_NAME_ARG", "")

    # Resolve remaining options (CLI > env vars > defaults)
    grafana_url: str = (
        args.grafana_url
        or os.environ.get("GRAFANA_URL_ARG", "")
        or "http://localhost:3000"
    )
    vault_addr: str = (
        args.vault_addr
        or os.environ.get("VAULT_ADDR_ARG", "")
        or "http://localhost:8200"
    )
    vault_mount: str = (
        args.vault_mount
        or os.environ.get("VAULT_MOUNT_ARG", "")
        or "grafana"
    )
    vault_namespace: str = args.vault_namespace or os.environ.get("VAULT_NAMESPACE_ARG", "")
    keycloak_url: str = args.keycloak_url or os.environ.get("KEYCLOAK_URL_ARG", "")
    backend: str = args.backend or os.environ.get("BACKEND_ARG", "")
    orgs: str = args.orgs or os.environ.get("ORGS_ARG", "")
    datasources: str = args.datasources or os.environ.get("DATASOURCES_ARG", "")
    dry_run: bool = args.dry_run

    project_root = Path(__file__).resolve().parent.parent

    # ── Validation ──────────────────────────────────────────────────────────
    if not env_name:
        print(f"{Colors.RED}Error: Environment name is required{Colors.NC}")
        print()
        print("  Usage: new_env.py <env-name> [options]")
        print("  Use --help for all options.")
        sys.exit(1)

    if not re.match(r"^[a-zA-Z][a-zA-Z0-9_-]*$", env_name):
        print(f"{Colors.RED}Error: Invalid environment name '{env_name}'{Colors.NC}")
        print(
            "Names must start with a letter and contain only letters, "
            "numbers, hyphens, and underscores."
        )
        sys.exit(1)

    if backend and backend not in {"s3", "azurerm", "gcs", "gitlab"}:
        print(f"{Colors.RED}Error: Invalid backend type '{backend}'{Colors.NC}")
        print("Supported: s3, azurerm, gcs, gitlab")
        sys.exit(1)

    env_path = project_root / "envs" / env_name
    if env_path.exists():
        print(f"{Colors.RED}Error: Environment '{env_name}' already exists!{Colors.NC}")
        print()
        print("Existing files:")
        if (env_path / "terraform.tfvars").is_file():
            print(f"  \u2713 envs/{env_name}/terraform.tfvars")
        if (env_path / "backend.tfbackend").is_file():
            print(f"  \u2713 envs/{env_name}/backend.tfbackend")
        if env_path.is_dir():
            print(f"  \u2713 envs/{env_name}/")
        if (env_path / "dashboards").is_dir():
            print(f"  \u2713 envs/{env_name}/dashboards/")
        print()
        print(f"To recreate, first run: make delete-env NAME={env_name}")
        sys.exit(1)

    # ── Header ──────────────────────────────────────────────────────────────
    print(f"{Colors.BOLD}{Colors.CYAN}")
    print("\u2554\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2557")
    print(f"\u2551          Creating New Environment: {env_name}")
    print("\u255a\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u255d")
    print(f"{Colors.NC}")

    print(f"  {Colors.DIM}Grafana URL:   {grafana_url}{Colors.NC}")
    vault_display = f"{vault_addr} (mount: {vault_mount})"
    if vault_namespace:
        vault_display += f" [ns: {vault_namespace}]"
    print(f"  {Colors.DIM}Vault:         {vault_display}{Colors.NC}")
    if keycloak_url:
        print(f"  {Colors.DIM}Keycloak:      {keycloak_url}{Colors.NC}")
    if backend:
        print(f"  {Colors.DIM}Backend:       {backend}{Colors.NC}")
    if orgs:
        print(f"  {Colors.DIM}Organizations: {orgs}{Colors.NC}")
    if datasources:
        print(f"  {Colors.DIM}Datasources:   {datasources}{Colors.NC}")
    if dry_run:
        print(f"  {Colors.DIM}Mode:          {Colors.YELLOW}DRY RUN{Colors.NC}")
    print()

    # ── Dry-run ─────────────────────────────────────────────────────────────
    if dry_run:
        print(f"{Colors.YELLOW}=== DRY RUN — No files will be created ==={Colors.NC}")
        print()
        print("  Would create:")
        print(f"    ✓ envs/{env_name}/terraform.tfvars")
        print(f"    ✓ envs/{env_name}/backend.tfbackend")
        print(f"    ✓ envs/{env_name}/")
        print("        ├── organizations.yaml")
        print("        ├── sso.yaml")
        print("        └── keycloak.yaml")
        print(f"    ✓ envs/{env_name}/alerting/   (one subdir per org)")
        print(f"    ✓ envs/{env_name}/dashboards/ (one subdir per org)")
        print(f"    ✓ envs/{env_name}/datasources/ (one subdir per org)")
        print(f"    ✓ envs/{env_name}/folders/     (one subdir per org)")
        print(f"    ✓ envs/{env_name}/teams/        (one subdir per org)")
        print(f"    ✓ envs/{env_name}/service_accounts/ (one subdir per org)")
        org_names = _get_org_names(orgs, project_root)
        for org in org_names:
            print(f"        └── {org}/")
        print()
        print(f"  Total: {Colors.BOLD}9+ files + per-org dirs{Colors.NC}")
        print()
        print("  To create for real, run without --dry-run")
        sys.exit(0)

    # ── Create files ─────────────────────────────────────────────────────────
    created_files: list[str] = []
    env_path.mkdir(parents=True, exist_ok=True)

    # 1. terraform.tfvars
    print(f"{Colors.BLUE}[1/5]{Colors.NC} Creating {Colors.YELLOW}envs/{env_name}/terraform.tfvars{Colors.NC}")
    tfvars_path = env_path / "terraform.tfvars"
    tfvars_path.write_text(
        _generate_tfvars(env_name, grafana_url, vault_addr, vault_mount,
                         vault_namespace, keycloak_url)
    )
    created_files.append(f"envs/{env_name}/terraform.tfvars")

    # 2. backend.tfbackend
    print(f"{Colors.BLUE}[2/5]{Colors.NC} Creating {Colors.YELLOW}envs/{env_name}/backend.tfbackend{Colors.NC}")
    backend_path = env_path / "backend.tfbackend"
    backend_path.write_text(_generate_backend(env_name, backend))
    created_files.append(f"envs/{env_name}/backend.tfbackend")

    # 3. YAML config files (base env files only)
    print(f"{Colors.BLUE}[3/5]{Colors.NC} Creating {Colors.YELLOW}envs/{env_name}/{Colors.NC} configuration files")

    yaml_files: list[tuple[str, str]] = [
        ("organizations.yaml", _generate_organizations(env_name)),
        ("sso.yaml", _generate_sso(env_name, vault_mount, keycloak_url)),
        ("keycloak.yaml", _generate_keycloak(env_name, vault_mount, keycloak_url)),
    ]
    for filename, content in yaml_files:
        (env_path / filename).write_text(content)

    created_files.append(f"envs/{env_name}/ (3 files)")

    # 4. Dashboard directories
    print(f"{Colors.BLUE}[4/5]{Colors.NC} Creating {Colors.YELLOW}envs/{env_name}/dashboards/{Colors.NC} directory structure")
    org_names = _get_org_names(orgs, project_root)
    for org in org_names:
        org_dir = env_path / "dashboards" / org
        org_dir.mkdir(parents=True, exist_ok=True)
        (org_dir / ".gitkeep").touch()
        print(f"       └── envs/{env_name}/dashboards/{Colors.CYAN}{org}{Colors.NC}/")

    created_files.append(f"envs/{env_name}/dashboards/ (dirs)")

    # 5. Resource directory structures (alerting, datasources, folders, teams, service_accounts)
    print(f"{Colors.BLUE}[5/5]{Colors.NC} Creating {Colors.YELLOW}envs/{env_name}/<resource>/{Colors.NC} directory structures")
    resource_types = ["alerting", "datasources", "folders", "teams", "service_accounts"]
    for res_type in resource_types:
        res_dir = env_path / res_type
        res_dir.mkdir(parents=True, exist_ok=True)
        for org in org_names:
            org_subdir = res_dir / org
            org_subdir.mkdir(parents=True, exist_ok=True)
            # For each organzation, create default templates inside the subdirectories
            if res_type == "alerting":
                (org_subdir / "alert_rules.yaml").write_text(_generate_alert_rules(env_name))
                (org_subdir / "contact_points.yaml").write_text(_generate_contact_points(env_name))
                (org_subdir / "notification_policies.yaml").write_text(_generate_notification_policies(env_name))
            else:
                tmpl_func = globals().get(f"_generate_{res_type}")
                if tmpl_func:
                    content = tmpl_func(env_name, vault_mount, "") if res_type == 'datasources' else tmpl_func(env_name)
                    (org_subdir / f"{res_type}.yaml").write_text(content)
        print(f"       └── envs/{env_name}/{res_type}/  ({len(org_names)} org dir(s) + default files)")

    for res_type in resource_types:
        created_files.append(f"envs/{env_name}/{res_type}/ (dirs + files)")

    # ── Summary ──────────────────────────────────────────────────────────────
    print()
    print(f"{Colors.BOLD}{Colors.GREEN}Environment '{env_name}' created successfully!{Colors.NC}")
    print()
    print(f"{Colors.BOLD}Created files:{Colors.NC}")
    for f in created_files:
        print(f"  {Colors.GREEN}\u2713{Colors.NC} {f}")

    print()
    print(f"{Colors.BOLD}Configuration:{Colors.NC}")
    print(f"  Grafana URL:   {Colors.BOLD}{grafana_url}{Colors.NC}")
    print(f"  Vault:         {Colors.BOLD}{vault_addr}{Colors.NC} (mount: {vault_mount})")
    if keycloak_url:
        print(f"  Keycloak:      {Colors.BOLD}{keycloak_url}{Colors.NC} {Colors.GREEN}(SSO enabled){Colors.NC}")
    if backend:
        print(f"  Backend:       {Colors.BOLD}{backend}{Colors.NC} {Colors.GREEN}(pre-configured){Colors.NC}")
    if datasources:
        print(f"  Datasources:   {Colors.BOLD}{datasources}{Colors.NC} {Colors.GREEN}(pre-configured){Colors.NC}")

    print()
    print(f"{Colors.BOLD}{Colors.YELLOW}Next steps:{Colors.NC}")

    step = 1
    if not keycloak_url and not datasources:
        print(
            f"  {Colors.CYAN}{step}.{Colors.NC} Edit {Colors.YELLOW}envs/{env_name}/terraform.tfvars{Colors.NC}"
            f" and {Colors.YELLOW}envs/{env_name}/*.yaml{Colors.NC} with your config"
        )
        step += 1

    print(
        f"  {Colors.CYAN}{step}.{Colors.NC} Add dashboard JSON files to "
        f"{Colors.YELLOW}envs/{env_name}/dashboards/{Colors.NC} or {Colors.YELLOW}base/dashboards/{Colors.NC}"
    )
    step += 1

    print(f"  {Colors.CYAN}{step}.{Colors.NC} Set up Vault secrets:")
    print(f"     {Colors.BOLD}make vault-setup ENV={env_name}{Colors.NC}")
    step += 1

    print(f"  {Colors.CYAN}{step}.{Colors.NC} Validate, initialize & deploy:")
    print(f"     {Colors.BOLD}make check-env ENV={env_name}{Colors.NC}")
    print(f"     {Colors.BOLD}make init ENV={env_name}{Colors.NC}")
    print(f"     {Colors.BOLD}make plan ENV={env_name}{Colors.NC}")
    print(f"     {Colors.BOLD}make apply ENV={env_name}{Colors.NC}")
    print()


if __name__ == "__main__":
    main()
