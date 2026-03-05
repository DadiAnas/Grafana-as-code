# Grafana as Code

[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.6.0-623CE4?logo=terraform)](https://terraform.io)
[![Grafana](https://img.shields.io/badge/Grafana-Provider%204.25.0-F46800?logo=grafana)](https://registry.terraform.io/providers/grafana/grafana)
[![Vault](https://img.shields.io/badge/Vault-Integrated-FFD814?logo=vault)](https://www.vaultproject.io/)
[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit)](https://pre-commit.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Manage your Grafana instance entirely as code using Terraform. Import an existing Grafana setup, or build one from scratch — organizations, folders, dashboards, datasources, teams, service accounts, alerting, and SSO are all defined in simple YAML files that are version-controlled, reviewable, and repeatable.

![Grafana as Code Architecture](docs/images/architecture.png)

---

## Table of Contents

- [Features](#-features)
- [Project Structure](#-project-structure)
- [Prerequisites](#-prerequisites)
- [Getting Started](#-getting-started)
- [Import from Grafana](#-import-from-grafana)
- [Configuration Reference](#-configuration-reference)
- [Terraform Workflow](#-terraform-workflow)
- [Environment Management](#-environment-management)
- [Operations](#-operations)
- [Vault & Secrets](#-vault--secrets)
- [CI/CD](#-cicd)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)

---

## ✨ Features

| Category | Capabilities |
|----------|-------------|
| **Import** | Auto-generate YAML + dashboard JSON from a running Grafana instance |
| **Multi-Environment** | Base + per-environment configs (`dev`, `staging`, `prod`, …) |
| **Multi-Organization** | Manage multiple Grafana orgs — resources keyed by composite `orgId:name` to prevent collisions |
| **Dashboards** | Version-controlled JSON dashboards, organized by org → folder |
| **Nested Folders** | Auto-discovered from directory structure with team-based permissions |
| **Alerting** | Alert rules, 20+ contact point types, notification policies, mute timings |
| **Datasources** | All datasource types with optional Vault-managed credentials |
| **SSO** | OAuth2/OIDC with wildcard org/group mappings (Keycloak, Okta, Azure AD, …) |
| **Team Sync** | Keycloak → Grafana team membership sync (OSS script or Enterprise native) |
| **Secrets** | HashiCorp Vault integration for all sensitive credentials |
| **Validation** | YAML schema validation (`make validate-config`) + pre-commit hooks |
| **CI/CD** | GitHub Actions + GitLab CI pipelines with lint, schema check, plan, apply |
| **Operations** | Drift detection, backup/restore, environment promotion, dashboard diff |

---

## 📁 Project Structure

```
grafana-as-code/
│
├── base/                             ← Shared config (applied to ALL environments)
│   ├── organizations.yaml
│   ├── sso.yaml
│   ├── keycloak.yaml
│   ├── alerting/
│   │   └── _default/                 ← Shared alerting defaults (empty by default)
│   │       ├── alert_rules.yaml
│   │       ├── contact_points.yaml
│   │       └── notification_policies.yaml
│   ├── datasources/
│   │   └── _default/datasources.yaml
│   ├── folders/
│   │   └── _default/folders.yaml
│   ├── teams/
│   │   └── _default/teams.yaml
│   ├── service_accounts/
│   │   └── _default/service_accounts.yaml
│   └── dashboards/                   ← Shared dashboards
│       └── <Org>/<folder>/*.json
│
├── envs/                             ← Per-environment (overrides base)
│   └── <env>/
│       ├── terraform.tfvars          ← Terraform variables
│       ├── backend.tfbackend         ← Remote state backend
│       ├── organizations.yaml        ← Environment-specific overrides
│       ├── sso.yaml
│       ├── keycloak.yaml
│       ├── datasources/              ← Per-org datasource files
│       │   └── <Org Name>/datasources.yaml
│       ├── folders/                  ← Per-org folder files
│       │   └── <Org Name>/folders.yaml
│       ├── teams/                    ← Per-org team files
│       │   └── <Org Name>/teams.yaml
│       ├── service_accounts/         ← Per-org service account files
│       │   └── <Org Name>/service_accounts.yaml
│       ├── alerting/                 ← Per-org alerting files
│       │   └── <Org Name>/
│       │       ├── alert_rules.yaml
│       │       ├── contact_points.yaml
│       │       └── notification_policies.yaml
│       └── dashboards/               ← Environment-specific dashboards
│           └── <Org>/<folder>/*.json
│
├── terraform/                        ← Infrastructure code (internal)
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── locals.tf
│   ├── backend.tf
│   └── modules/
│       ├── organizations/
│       ├── folders/
│       ├── datasources/
│       ├── dashboards/
│       ├── alerting/
│       ├── teams/
│       ├── service_accounts/
│       ├── sso/
│       └── keycloak/
│
├── scripts/                          ← Automation
│   ├── import_from_grafana.py         ← Import from existing Grafana
│   ├── validate_config.py            ← YAML schema validation
│   ├── new_env.py                    ← Create new environment
│   ├── check_env.py                  ← Validate environment structure
│   ├── delete_env.py
│   ├── promote.py
│   ├── backup.py
│   └── vault/                        ← Vault setup scripts
│       └── ...
│
├── schemas/                          ← YAML validation schemas
│   ├── datasources.schema.yaml
│   ├── folders.schema.yaml
│   ├── teams.schema.yaml
│   ├── service_accounts.schema.yaml
│   ├── alert_rules.schema.yaml
│   ├── contact_points.schema.yaml
│   ├── notification_policies.schema.yaml
│   └── organizations.schema.yaml
│
├── Makefile                          ← Entry point — run everything from here
├── README.md
├── .pre-commit-config.yaml           ← Git pre-commit hooks
├── docker-compose.yml                ← Local dev: Grafana + Vault + Keycloak
└── .github/ / .gitlab-ci.yml        ← CI/CD pipelines
```

**Day-to-day, you only interact with 2 directories:**

| What you do | Where |
|-------------|-------|
| Edit shared config (all envs) | `base/*.yaml` or `base/<resource>/_default/` |
| Edit env-specific config | `envs/<env>/<Org Name>/` subdirectories |
| Run commands | `make plan ENV=prod` |

Everything else (`terraform/`, `scripts/`, `modules/`) is internal plumbing.

---

## 📋 Prerequisites

- **Terraform** >= 1.6.0
- **Python 3** (used by the import script)
- **curl** (used by API scripts)
- **Grafana** instance with admin access (basic auth or service account token)
- **HashiCorp Vault** for secrets management
- **Docker** *(optional)* for local development
- **Keycloak** *(optional)* for SSO

---

## 🚀 Getting Started

### Option A: Import from an Existing Grafana *(recommended)*

The fastest way to adopt Grafana-as-Code is to import your existing Grafana configuration.

```bash
# 1. Import everything from your Grafana instance
make import ENV=prod \
  GRAFANA_URL=https://grafana.example.com \
  AUTH=admin:password

# 2. Review the generated files
ls envs/prod/
ls envs/prod/dashboards/

# 3. Set up Vault secrets
export VAULT_TOKEN="your-token"
make vault-setup ENV=prod

# 4. Initialize and apply
make init  ENV=prod
make plan  ENV=prod    # ← Review the plan carefully
make apply ENV=prod
```

> See the [Import from Grafana](#-import-from-grafana) section for full details.

### Option B: Build from Scratch

```bash
# 1. Scaffold a new environment
make new-env NAME=staging \
  GRAFANA_URL=https://grafana.example.com \
  DATASOURCES=prometheus,loki,postgres \
  BACKEND=s3

# 2. Edit the generated YAML files
vim envs/staging/datasources.yaml
vim envs/staging/teams.yaml

# 3. Add dashboards
cp my-dashboard.json envs/staging/dashboards/MainOrg/infrastructure/

# 4. Set up Vault, then deploy
make vault-setup ENV=staging
make init  ENV=staging
make plan  ENV=staging
make apply ENV=staging
```

> **Tip:** Edit `envs/staging/datasources/<Org>/datasources.yaml`, `envs/staging/teams/<Org>/teams.yaml`, etc. Files are organized per-org subdirectory.

### Option C: Local Development

```bash
# 1. Start Grafana + Vault + Keycloak locally
make dev-up

# 2. Bootstrap dev environment
make dev-bootstrap

# 3. Deploy
export VAULT_TOKEN=root
make init ENV=dev && make plan ENV=dev && make apply ENV=dev
```

---

## 📥 Import from Grafana

The import script (`scripts/import_from_grafana.py`) connects to a running Grafana instance and auto-generates all the YAML configuration files and dashboard JSON needed to manage it with Terraform.

### What Gets Imported

| Resource | Output | Notes |
|----------|--------|-------|
| Organizations | `envs/<env>/organizations.yaml` | All orgs with ID mappings |
| Folders | `envs/<env>/folders/<Org>/folders.yaml` | Per-org; UIDs slugified from titles |
| Dashboards | `envs/<env>/dashboards/<Org>/<folder>/` | JSON files, stripped of `id` and `version` |
| Datasources | `envs/<env>/datasources/<Org>/datasources.yaml` | Per-org; secrets must be added to Vault |
| Teams | `envs/<env>/teams/<Org>/teams.yaml` | Per-org |
| Service Accounts | `envs/<env>/service_accounts/<Org>/service_accounts.yaml` | Per-org; tokens must be re-created |
| Alert Rules | `envs/<env>/alerting/<Org>/alert_rules.yaml` | Per-org; grouped by folder + rule group |
| Contact Points | `envs/<env>/alerting/<Org>/contact_points.yaml` | Per-org; all notifier types |
| Notification Policies | `envs/<env>/alerting/<Org>/notification_policies.yaml` | Per-org; full routing tree |
| SSO Settings | `envs/<env>/sso.yaml` | OAuth config with group→org mappings |
| Terraform Variables | `envs/<env>/terraform.tfvars` | Grafana URL, Vault config |

### Usage

```bash
# Basic import
make import ENV=prod \
  GRAFANA_URL=https://grafana.example.com \
  AUTH=admin:password

# Using an API token instead of basic auth
make import ENV=prod \
  GRAFANA_URL=https://grafana.example.com \
  AUTH=glsa_xxxxxxxxxxxxx

# Skip dashboards (faster, config-only import)
python3 scripts/import_from_grafana.py prod \
  --grafana-url=https://grafana.example.com \
  --auth=admin:password \
  --no-dashboards
```

### Command Options

| Option | Description |
|--------|-------------|
| `<env-name>` | *(required)* Target environment name |
| `--grafana-url=<url>` | *(required)* Grafana instance URL |
| `--auth=<credentials>` | *(required)* `user:password` or API token |
| `--no-dashboards` | Skip dashboard JSON export |
| `--output-dir=<path>` | Custom output directory (default: project root) |

### Post-Import Steps

1. **Review all generated YAML files** — adjust names, roles, and settings as needed
2. **Set up Vault secrets** — datasource passwords, SSO client secrets, etc. are not exported
3. **Run `terraform plan`** — review the plan carefully before applying
4. **Apply** — Terraform will create all resources with the imported configuration

---

## 📖 Configuration Reference

### Merge Behavior

All resources follow a **base + environment override** pattern. Environment-specific configs override base configs that have the same merge key.

```
base/datasources/_default/datasources.yaml   →  Foundation (applied everywhere)
envs/staging/datasources/<Org>/datasources.yaml  →  Overrides for staging only
```

| Resource | Merge Key |
|----------|-----------|
| Organizations | `name` |
| Folders | `orgId:uid` |
| Teams | `name/orgId` |
| Service Accounts | `orgId:name` |
| Datasources | `orgId:uid` |
| Alert Rules | `orgId:folder-name` |
| Contact Points | `orgId:name` |
| Notification Policies | `orgId` |
| Dashboards | `filepath` (env overrides base) |

### Multi-Organization Support

All resources are organized in **per-org subdirectories** within each environment. This eliminates Terraform `for_each` duplicate key errors and makes the relationship between resources and organizations explicit:

```
envs/prod/
  datasources/
    Main Org./datasources.yaml    # orgId: 1
    Platform Team/datasources.yaml # orgId: 3
  alerting/
    Main Org./contact_points.yaml
    Platform Team/alert_rules.yaml
```

Each resource uses `orgId` (numeric) instead of `org` (name string) when importable from Grafana:

```yaml
# envs/prod/datasources/Main Org./datasources.yaml
datasources:
  - name: "Prometheus"
    uid: "prometheus-main"
    orgId: 1         # numeric org ID
    type: "prometheus"
    url: "http://prometheus:9090"
```

### Organizations

```yaml
# base/organizations.yaml
organizations:
  - name: "Engineering"
  - name: "Business Intelligence"
```

### Folders & Dashboards

```yaml
# base/folders.yaml
folders:
  - title: "Infrastructure"
    uid: "infrastructure"
    org: "Engineering"
    permissions:
      - team: "SRE"
        permission: "Edit"
      - role: "Viewer"
        permission: "View"
```

Dashboard JSON files go into:
```
base/dashboards/<Org>/<folder-uid>/my-dashboard.json         # All environments
envs/<env>/dashboards/<Org>/<folder-uid>/my-dashboard.json   # Specific environment
```

### Datasources

```yaml
# envs/prod/datasources/Main Org./datasources.yaml
datasources:
  - name: "Prometheus"
    type: "prometheus"
    uid: "prometheus"
    url: "http://prometheus:9090"
    orgId: 1              # numeric org ID
    is_default: true
    use_vault: true       # Load secrets from Vault
```

### SSO / OAuth2

```yaml
# envs/prod/sso.yaml
sso:
  enabled: true
  name: "Keycloak"
  auth_url: "https://sso.example.com/realms/main/protocol/openid-connect/auth"
  token_url: "https://sso.example.com/realms/main/protocol/openid-connect/token"
  api_url: "https://sso.example.com/realms/main/protocol/openid-connect/userinfo"
  client_id: "grafana"

  groups:
    # Named group → specific org
    - name: "sre-team"
      org_mappings:
        - orgId: 1
          role: "Admin"

    # Wildcard: all groups → all orgs
    - name: "*"
      wildcard_group: true
      org_mappings:
        - orgId: "*"
          role: "Viewer"
```

---

## ⚙️ Terraform Workflow

```bash
make init  ENV=<env>               # Initialize Terraform
make plan  ENV=<env>               # Preview changes
make apply ENV=<env>               # Deploy
make destroy ENV=<env>             # Tear down (with confirmation)
```

All `terraform` commands run via `terraform -chdir=terraform` — you always execute `make` from the project root.

---

## 🌍 Environment Management

![Grafana as Code Environments](docs/images/environments.png)

```bash
make new-env NAME=staging GRAFANA_URL=https://grafana.example.com
make list-envs
make check-env ENV=staging
make delete-env NAME=staging
make dry-run NAME=staging
```

### `new-env` Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `NAME` | *(required)* Environment name | — |
| `GRAFANA_URL` | Grafana instance URL | `http://localhost:3000` |
| `VAULT_ADDR` | Vault server address | `http://localhost:8200` |
| `VAULT_MOUNT` | Vault KV mount path | `grafana` |
| `KEYCLOAK_URL` | Keycloak URL (enables SSO config) | *(disabled)* |
| `BACKEND` | Backend type: `s3`, `azurerm`, `gcs`, `gitlab` | *(local)* |
| `ORGS` | Organizations (comma-separated) | *(from base config)* |
| `DATASOURCES` | Datasource presets (comma-separated) | *(empty)* |

---

## 🔧 Operations

| Command | Description |
|---------|-------------|
| `make drift ENV=staging` | Detect changes made outside Terraform |
| `make backup ENV=prod` | Snapshot Grafana's live state via API |
| `make promote FROM=staging TO=prod` | Diff and copy configs between environments |
| `make dashboard-diff ENV=staging` | Human-readable dashboard change summary |
| `make team-sync ENV=prod GRAFANA_URL=... AUTH=... KEYCLOAK_URL=... KEYCLOAK_USER=... KEYCLOAK_PASS=...` | Sync Keycloak → Grafana teams |

---

## 🔐 Vault & Secrets

```bash
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='your-root-token'

make vault-setup ENV=staging       # Create secrets
make vault-verify ENV=staging      # Verify secrets exist
```

Datasources with `use_vault: true` automatically load credentials from Vault.

---

## 🔄 CI/CD

![Grafana as Code CI/CD Merge Workflow](docs/images/merge-workflow.png)

### GitHub Actions

1. **On PR** — `fmt`, `validate`, YAML lint, **schema validation**, `tflint`, `terraform plan` posted as PR comment
2. **On merge** — `terraform apply` with GitHub Environment protection
3. **On schedule** — Drift detection, creates GitHub Issue if changes found

### GitLab CI

1. **validate** — `fmt`, `validate`, YAML lint, **schema validation**, `tfsec` security scan
2. **plan** — Per-environment plans with artifacts
3. **apply** — Manual or auto-apply per environment
4. **drift** — Scheduled pipeline

### Local Validation

```bash
# Install pre-commit hooks (one-time setup)
make pre-commit-install

# Now every git commit automatically runs:
#   → trailing whitespace / end-of-file fixes
#   → YAML lint (base/ and envs/ only)
#   → YAML schema validation (schemas/*.schema.yaml)

# Run all checks manually without committing
make pre-commit-run

# Validate YAML schemas only
make validate-config             # all environments
make validate-config ENV=prod    # single environment
```

---

## 🐛 Troubleshooting

| Issue | Solution |
|-------|----------|
| `for_each` duplicate key error | Resources use per-org subdirs (`envs/<env>/<resource>/<Org>/`). Ensure each org subdir has a unique name matching the Grafana org name |
| Permission denied | Ensure Grafana credentials have `Admin` role |
| Vault secret not found | Run `make vault-verify ENV=<env>` then `make vault-setup ENV=<env>` |
| Dashboard import fails | Validate JSON syntax; check folder UID matches directory name |
| SSO wildcard `*` not working | Use `wildcard_group: true` flag for `name: "*"` groups |
| Where did `*.tf` files go? | They're in `terraform/`. The Makefile handles `-chdir` automatically |
| Missing per-org dirs after import | Run `make import ENV=<env>` again — all org dirs are now always created even if empty |

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Install pre-commit hooks: `make pre-commit-install`
4. Make changes and commit — hooks run automatically
5. Push to branch (`git push origin feature/my-feature`)
6. Open a Pull Request

> Pre-commit hooks check YAML syntax, style, and schema validation before every commit.
> To skip for a one-off commit: `git commit --no-verify`

## 📄 License

MIT License — See [LICENSE](LICENSE) for details.
