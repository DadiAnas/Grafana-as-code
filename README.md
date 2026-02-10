# Grafana as Code with Terraform

[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.0.0-623CE4?logo=terraform)](https://terraform.io)
[![Grafana](https://img.shields.io/badge/Grafana-Provider%204.25.0-F46800?logo=grafana)](https://registry.terraform.io/providers/grafana/grafana)
[![Vault](https://img.shields.io/badge/Vault-Integrated-FFD814?logo=vault)](https://www.vaultproject.io/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Manage your **existing Grafana instance** entirely as code using Terraform. Define organizations, folders, dashboards, datasources, teams, alerting, and SSO in simple YAML files — version-controlled, reviewable, and repeatable.

![Architecture Overview](docs/images/architecture.png)

## 🎯 Features

- **Multi-Environment**: Separate configs per environment (dev, staging, production, etc.)
- **Multi-Organization**: Manage multiple Grafana orgs with role-based access
- **Nested Folders**: Auto-discovered from directory structure with optional permissions
- **Dashboard as Code**: Version-controlled JSON dashboards organized by folder
- **Full Alerting**: Alert rules, 20+ contact point types, notification policies, mute timings
- **Dynamic Datasources**: All datasource types with Vault-managed credentials
- **SSO Integration**: OAuth2/OIDC (Keycloak, Okta, Azure AD, etc.)
- **Secrets Management**: HashiCorp Vault for all sensitive credentials
- **CI/CD Ready**: GitLab CI pipeline included (adapt for GitHub Actions, etc.)

## 📁 Project Structure

```
grafana-as-code/
├── main.tf                          # Providers, modules, and wiring
├── variables.tf                     # Input variables (Grafana URL, Vault, etc.)
├── outputs.tf                       # Terraform outputs
├── locals.tf                        # Config loading & merging logic
├── backend.tf                       # Remote state backend (commented examples)
│
├── environments/                    # One .tfvars file per environment
│   └── myenv.tfvars                # ← Your environment config
│
├── backends/                        # Remote state backend configs
│   └── myenv.tfbackend             # ← S3/Azure/GCS backend (optional)
│
├── config/                          # YAML configuration
│   ├── shared/                     # Shared across ALL environments
│   │   ├── organizations.yaml      # Grafana organizations
│   │   ├── folders.yaml            # Folder permissions (optional)
│   │   ├── teams.yaml              # Teams
│   │   ├── datasources.yaml        # Datasources
│   │   ├── service_accounts.yaml   # Service accounts
│   │   ├── sso.yaml                # SSO/OAuth config
│   │   ├── keycloak.yaml           # Keycloak client management (optional)
│   │   └── alerting/
│   │       ├── alert_rules.yaml
│   │       ├── contact_points.yaml
│   │       └── notification_policies.yaml
│   │
│   └── myenv/                      # Environment-specific overrides
│       ├── organizations.yaml      # (same file structure as shared/)
│       ├── datasources.yaml
│       ├── folders.yaml
│       ├── teams.yaml
│       ├── service_accounts.yaml
│       ├── sso.yaml
│       ├── keycloak.yaml
│       └── alerting/
│           ├── alert_rules.yaml
│           ├── contact_points.yaml
│           └── notification_policies.yaml
│
├── dashboards/                      # Dashboard JSON files
│   ├── README.md                   # Detailed directory structure guide
│   ├── shared/                     # Deployed to ALL environments
│   │   └── <Org Name>/
│   │       └── <folder-uid>/
│   │           └── dashboard.json
│   └── myenv/                      # Deployed ONLY to myenv
│       └── <Org Name>/
│           └── <folder-uid>/
│               └── dashboard.json
│
├── modules/                         # Terraform modules
│   ├── organizations/              # Org management
│   ├── folders/                    # Folder creation & permissions
│   ├── datasources/                # Datasource provisioning
│   ├── dashboards/                 # Dashboard deployment
│   ├── alerting/                   # Alert rules, contacts, policies
│   ├── teams/                      # Team management
│   ├── service_accounts/           # Service account management
│   ├── sso/                        # SSO configuration
│   ├── keycloak/                   # Keycloak client (optional)
│   └── vault/                      # Vault secrets integration
│
├── vault/                           # Vault setup scripts
│   ├── policies/
│   │   └── grafana-terraform.hcl
│   └── scripts/
│       ├── setup-secrets.sh        # Create secrets for an environment
│       ├── setup-all-secrets.sh    # Multi-environment setup
│       ├── verify-secrets.sh       # Check secrets exist
│       ├── rotate-secret.sh        # Rotate a secret
│       └── bootstrap-secrets.sh    # One-time Vault init
│
├── .gitlab-ci.yml                   # GitLab CI/CD pipeline
└── Makefile                         # Automation shortcuts
```

## 🔄 Configuration Merge Behavior

All resources follow a **shared + environment override** pattern:

![Configuration Merge Pattern](docs/images/merge-workflow.png)

| Resource | Shared Location | Env Override | Merge Key |
|----------|----------------|--------------|-----------|
| Organizations | `config/shared/organizations.yaml` | `config/<env>/organizations.yaml` | `name` |
| Folders | `config/shared/folders.yaml` | `config/<env>/folders.yaml` | `uid` |
| Teams | `config/shared/teams.yaml` | `config/<env>/teams.yaml` | `name` |
| Datasources | `config/shared/datasources.yaml` | `config/<env>/datasources.yaml` | `uid` |
| Alert Rules | `config/shared/alerting/alert_rules.yaml` | `config/<env>/alerting/alert_rules.yaml` | `folder-name` |
| Contact Points | `config/shared/alerting/contact_points.yaml` | `config/<env>/alerting/contact_points.yaml` | `name` |
| Notification Policies | `config/shared/alerting/notification_policies.yaml` | `config/<env>/alerting/notification_policies.yaml` | `org` |
| Dashboards | `dashboards/shared/` | `dashboards/<env>/` | filename |

**Environment-specific configs override shared configs** with the same merge key.

## 📋 Prerequisites

- **Terraform** >= 1.0.0
- **Grafana** instance with admin access (API key or service account token)
- **HashiCorp Vault** for secrets management
- **Keycloak** (optional) for SSO

## 🚀 Quick Start

### 1. Clone the repository

```bash
git clone <repository-url>
cd grafana-as-code
```

### 2. Create your environment

Use the built-in scaffolding to create all files in one command:

```bash
# Create a new environment with your Grafana URL
make new-env NAME=staging GRAFANA_URL=https://grafana.example.com
```

This creates everything you need:
- `environments/staging.tfvars` — Terraform variables
- `backends/staging.tfbackend` — Remote state config (optional)
- `config/staging/` — 10 YAML config files
- `dashboards/staging/` — Dashboard directories per organization

### 3. Check your environment

```bash
# Validate that everything is in place
make check-env ENV=staging
```

### 4. Set up Vault secrets

```bash
# Set Vault connection
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='your-root-token'

# Create secrets (edit vault/scripts/setup-secrets.sh first with real values)
make vault-setup ENV=staging

# Verify
make vault-verify ENV=staging
```

### 5. Add your configuration

Edit the YAML files in `config/shared/` — each file has commented examples:

```yaml
# config/shared/datasources.yaml
datasources:
  - name: "Prometheus"
    type: "prometheus"
    uid: "prometheus"
    url: "http://prometheus:9090"
    org: "Main Organization"
    is_default: true
```

### 6. Add dashboards

Drop Grafana dashboard JSON files into the folder structure:

```
dashboards/shared/Main Organization/infrastructure/my-dashboard.json
```

### 7. Initialize and deploy

```bash
make init  ENV=staging
make plan  ENV=staging
make apply ENV=staging
```

## 🛠️ Environment Management

![Multi-Environment Deployment](docs/images/environments.png)

Create, list, check, and delete environments with simple Make commands:

```bash
# Create a new environment (scaffolds all files)
make new-env NAME=production GRAFANA_URL=https://grafana.example.com

# List all environments with status
make list-envs

# Pre-deployment validation
make check-env ENV=production

# Delete an environment's scaffolding (NOT infrastructure — use destroy first)
make delete-env NAME=production
```

### `new-env` optional parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `NAME` | **(required)** Environment name | — |
| `GRAFANA_URL` | Grafana instance URL | `http://localhost:3000` |
| `VAULT_ADDR` | Vault server address | `http://localhost:8200` |
| `VAULT_MOUNT` | Vault KV mount path | `grafana` |
| `VAULT_NAMESPACE` | Vault Enterprise namespace | *(root namespace)* |
| `KEYCLOAK_URL` | Keycloak URL (enables SSO config) | *(disabled)* |
| `BACKEND` | Backend type: `s3`, `azurerm`, `gcs` | *(all commented)* |
| `ORGS` | Custom organizations (comma-separated) | *(from shared config)* |
| `DATASOURCES` | Datasource presets (comma-separated) | *(empty)* |

**Supported datasource presets:** `prometheus`, `loki`, `postgres`, `mysql`, `elasticsearch`, `influxdb`, `tempo`, `mimir`, `cloudwatch`, `graphite`

### Advanced examples

```bash
# Minimal — just a name
make new-env NAME=dev

# Full stack — Prometheus, Loki, Postgres with S3 backend and SSO
make new-env NAME=production \
  GRAFANA_URL=https://grafana.prod.example.com \
  BACKEND=s3 \
  DATASOURCES=prometheus,loki,postgres \
  KEYCLOAK_URL=https://sso.example.com

# Custom organizations
make new-env NAME=multi-org \
  ORGS="Engineering,Product,Business Intelligence" \
  DATASOURCES=prometheus

# Azure with custom Vault
make new-env NAME=azure-prod \
  GRAFANA_URL=https://grafana.azure.example.com \
  BACKEND=azurerm \
  VAULT_ADDR=https://vault.azure.example.com \
  VAULT_MOUNT=grafana-prod
```

### What `new-env` creates

```
environments/production.tfvars         ← Grafana URL, Vault config
backends/production.tfbackend          ← S3/Azure/GCS backend (auto-uncommented if BACKEND set)
config/production/                     ← 10 YAML override files
  ├── organizations.yaml
  ├── datasources.yaml                ← pre-filled if DATASOURCES set
  ├── folders.yaml
  ├── teams.yaml
  ├── service_accounts.yaml
  ├── sso.yaml                        ← pre-filled if KEYCLOAK_URL set
  ├── keycloak.yaml                   ← pre-filled if KEYCLOAK_URL set
  └── alerting/
      ├── alert_rules.yaml
      ├── contact_points.yaml
      └── notification_policies.yaml
dashboards/production/                 ← Dashboard dirs per org (custom if ORGS set)
  └── Main Organization/
```

## 🔧 Common Operations

```bash
# ─── Environment Management ───
make new-env NAME=dev                          # Create environment
make list-envs                                 # List all environments
make check-env ENV=dev                         # Validate readiness
make delete-env NAME=dev                       # Delete scaffolding

# ─── Terraform Workflow ───
make init  ENV=staging                         # Initialize
make plan  ENV=staging                         # Preview changes
make apply ENV=staging                         # Deploy
make destroy ENV=staging                       # Tear down (with confirmation)

# ─── Vault ───
make vault-setup  ENV=staging                  # Create Vault secrets
make vault-verify ENV=staging                  # Check secrets exist

# ─── Utilities ───
make fmt                                       # Format Terraform files
make validate                                  # Validate configuration
make output ENV=staging                        # Show outputs
make state-list                                # List managed resources
make clean                                     # Remove cache & plan files

# ─── Debug ───
TF_LOG=DEBUG terraform apply -var-file=environments/staging.tfvars
```

## 📤 Outputs

After applying, Terraform exposes:

| Output | Description |
|--------|-------------|
| `organization_ids` | Map of org names → IDs |
| `folder_ids` | Map of folder paths → IDs |
| `folder_uids` | Map of folder paths → UIDs |
| `datasource_ids` | Map of datasource names → IDs |
| `dashboard_urls` | Map of dashboard names → URLs |
| `team_ids` | Map of team names → IDs |
| `service_account_ids` | Map of service account names → IDs |

## 🐛 Troubleshooting

| Issue | Solution |
|-------|----------|
| Permission denied | Ensure Grafana credentials have `Admin` role |
| Vault secret not found | `make vault-verify ENV=<name>` then `make vault-setup ENV=<name>` |
| Dashboard import fails | Validate JSON syntax before applying |
| Folder cycle error | Split folders into top-level and subfolders (max 2 levels deep) |
| Environment incomplete | `make check-env ENV=<name>` to see what's missing |

## 🖼️ Visual Overview

### Multi-Organization Support
Manage multiple isolated organizations from a single Terraform configuration:

![Organizations](docs/images/multi-org.png)

### SSO Integration
Single Sign-On login page with Keycloak/OIDC integration:

![SSO Login](docs/images/sso.png)

### Datasources Management
Configured datasources deployed via Terraform:

![Datasources](docs/images/grafana.png)

### Keycloak Group Mapping
Map IdP groups to Grafana organizations and roles:

![Keycloak Mapping](docs/images/keycloak%20multi-team%20org%20mapping.png)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit changes (`git commit -am 'Add new feature'`)
4. Push to branch (`git push origin feature/my-feature`)
5. Open a Pull Request

## 📄 License

MIT License — See [LICENSE](LICENSE) for details.
