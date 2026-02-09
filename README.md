# Grafana as Code with Terraform

[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.0.0-623CE4?logo=terraform)](https://terraform.io)
[![Grafana](https://img.shields.io/badge/Grafana-Provider%204.25.0-F46800?logo=grafana)](https://registry.terraform.io/providers/grafana/grafana)
[![Vault](https://img.shields.io/badge/Vault-Integrated-FFD814?logo=vault)](https://www.vaultproject.io/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Manage your **existing Grafana instance** entirely as code using Terraform. Define organizations, folders, dashboards, datasources, teams, alerting, and SSO in simple YAML files — version-controlled, reviewable, and repeatable.

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

### 2. Configure your environment

Edit `environments/myenv.tfvars` with your Grafana URL:

```hcl
grafana_url = "https://grafana.example.com"
environment = "myenv"
vault_address = "http://localhost:8200"
```

### 3. Set up Vault secrets

```bash
# Start Vault (development mode for testing)
vault server -dev

# In another terminal
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='your-root-token'

# Create the required secrets (edit the script first with real values)
bash vault/scripts/setup-secrets.sh myenv

# Verify
bash vault/scripts/verify-secrets.sh myenv
```

### 4. Add your configuration

Edit the YAML files in `config/shared/` — each file has commented examples:

```yaml
# config/shared/organizations.yaml
organizations:
  - name: "Main Organization"
    id: 1

# config/shared/datasources.yaml
datasources:
  - name: "Prometheus"
    type: "prometheus"
    uid: "prometheus"
    url: "http://prometheus:9090"
    org: "Main Organization"
    is_default: true
```

### 5. Add dashboards

Drop Grafana dashboard JSON files into the folder structure:

```
dashboards/shared/Main Organization/infrastructure/my-dashboard.json
```

### 6. Initialize and apply

```bash
# Using Make
make init ENV=myenv
make plan ENV=myenv
make apply ENV=myenv

# Or directly with Terraform
terraform init
terraform plan  -var-file=environments/myenv.tfvars
terraform apply -var-file=environments/myenv.tfvars
```

## ➕ Adding a New Environment

1. **Create tfvars**: Copy `environments/myenv.tfvars` → `environments/staging.tfvars`
2. **Create backend** (optional): Copy `backends/myenv.tfbackend` → `backends/staging.tfbackend`
3. **Create config**: Copy `config/myenv/` → `config/staging/`
4. **Create dashboards**: `mkdir -p "dashboards/staging/Main Organization"`
5. **Set up Vault**: `bash vault/scripts/setup-secrets.sh staging`
6. **Apply**: `make init ENV=staging && make plan ENV=staging`

## 🔧 Common Operations

```bash
# Format Terraform files
make fmt

# Validate configuration
make validate

# Show current state
make state-list

# Show outputs
make output ENV=myenv

# Destroy everything (careful!)
make destroy ENV=myenv

# Debug mode
TF_LOG=DEBUG terraform apply -var-file=environments/myenv.tfvars
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
| Vault secret not found | Run `bash vault/scripts/verify-secrets.sh myenv` |
| Dashboard import fails | Validate JSON syntax before applying |
| Folder cycle error | Split folders into top-level and subfolders (max 2 levels deep) |

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit changes (`git commit -am 'Add new feature'`)
4. Push to branch (`git push origin feature/my-feature`)
5. Open a Pull Request

## 📄 License

MIT License — See [LICENSE](LICENSE) for details.
