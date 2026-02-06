# HashiCorp Vault Integration Guide

This guide covers the complete setup and usage of HashiCorp Vault for managing Grafana secrets in this Terraform project.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Vault Secret Structure](#vault-secret-structure)
- [Setup Scripts](#setup-scripts)
- [Configuration Reference](#configuration-reference)
- [Authentication Methods](#authentication-methods)
- [CI/CD Integration](#cicd-integration)
- [Security Best Practices](#security-best-practices)
- [Troubleshooting](#troubleshooting)

## Overview

All sensitive credentials in this project are stored in HashiCorp Vault and retrieved at runtime by Terraform. This provides:

- **Centralized secrets management**: Single source of truth for all credentials
- **Audit logging**: Track who accessed what secrets and when
- **Secret rotation**: Easy credential rotation without code changes
- **Access control**: Fine-grained policies for different teams/environments
- **Encryption**: Secrets encrypted at rest and in transit

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Terraform     │────▶│   HashiCorp     │────▶│    Grafana      │
│   (Client)      │     │   Vault         │     │   Instance      │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │
        │   1. Authenticate     │
        │──────────────────────▶│
        │                       │
        │   2. Fetch secrets    │
        │──────────────────────▶│
        │                       │
        │   3. Apply config     │
        │──────────────────────────────────────▶│
```

## Quick Start

### 1. Start Vault (Development Mode)

```bash
# Start Vault in dev mode (NOT for production!)
vault server -dev

# Note the root token displayed in the output
# Example: Root Token: hvs.xxxxxxxxxxxxx
```

### 2. Configure Environment

```bash
# Set Vault address and token
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='hvs.xxxxxxxxxxxxx'  # Your root token

# Verify connection
vault status
```

### 3. Run Setup Script

```bash
# Setup secrets for NPR environment
./vault/scripts/setup-npr-secrets.sh

# Or setup all environments
./vault/scripts/setup-all-secrets.sh --all
```

### 4. Verify Secrets

```bash
# Verify all required secrets exist
./vault/scripts/verify-secrets.sh npr
```

### 5. Run Terraform

```bash
terraform init
terraform plan -var-file=environments/npr.tfvars
terraform apply -var-file=environments/npr.tfvars
```

## Vault Secret Structure

Secrets are organized by environment under the `grafana/` KV v2 mount:

```
grafana/                                    # KV v2 Secrets Engine
├── npr/                                    # NPR Environment
│   ├── grafana/
│   │   └── auth                           # credentials="admin:password"
│   ├── datasources/
│   │   ├── InfluxDB                       # token="influx-token"
│   │   ├── PostgreSQL                     # user="user", password="pass"
│   │   ├── Elasticsearch                  # basicAuthUser, basicAuthPassword
│   │   ├── MySQL                          # user, password
│   │   ├── Prometheus                     # basicAuthPassword
│   │   └── Loki                           # basicAuthPassword
│   ├── alerting/
│   │   └── contact-points/
│   │       └── webhook-npr                # authorization_credentials="token"
│   ├── sso/
│   │   └── keycloak                       # client_id, client_secret
│   └── smtp                               # user, password
│
├── preprod/                               # PreProd Environment
│   └── (same structure as npr)
│
└── prod/                                  # Production Environment
    ├── grafana/
    │   └── auth
    ├── datasources/
    │   └── (same as npr)
    ├── alerting/
    │   └── contact-points/
    │       ├── webhook-prod               # Standard alerts
    │       └── webhook-critical           # Critical alerts
    ├── sso/
    │   └── keycloak
    └── smtp
```

### Secret Key Reference

| Secret Path | Keys | Description |
|-------------|------|-------------|
| `{env}/grafana/auth` | `credentials` | Format: `username:password` |
| `{env}/datasources/{name}` | Varies by type | See datasource section |
| `{env}/alerting/contact-points/{name}` | `authorization_credentials` | Bearer token for webhooks |
| `{env}/sso/keycloak` | `client_id`, `client_secret` | OAuth client credentials |
| `{env}/smtp` | `user`, `password` | SMTP authentication |

### Datasource Credential Keys

| Datasource Type | Required Keys |
|----------------|---------------|
| PostgreSQL/MySQL | `user`, `password` |
| InfluxDB | `token` |
| Elasticsearch | `basicAuthUser`, `basicAuthPassword` |
| Prometheus/Loki | `basicAuthPassword` (if auth enabled) |

## Setup Scripts

### Available Scripts

| Script | Description |
|--------|-------------|
| `setup-npr-secrets.sh` | Create NPR environment secrets |
| `setup-preprod-secrets.sh` | Create PreProd environment secrets |
| `setup-prod-secrets.sh` | Create Production secrets (with confirmation) |
| `setup-all-secrets.sh` | Interactive multi-environment setup |
| `verify-secrets.sh` | Verify all required secrets exist |
| `rotate-secret.sh` | Rotate individual secrets |
| `bootstrap-secrets.sh` | Quick bootstrap with defaults |

### Usage Examples

```bash
# Setup single environment
./vault/scripts/setup-npr-secrets.sh

# Setup all environments interactively
./vault/scripts/setup-all-secrets.sh

# Setup specific environments via flags
./vault/scripts/setup-all-secrets.sh --npr --preprod

# Verify secrets exist
./vault/scripts/verify-secrets.sh npr
./vault/scripts/verify-secrets.sh prod

# Rotate a specific secret
./vault/scripts/rotate-secret.sh prod datasource PostgreSQL
./vault/scripts/rotate-secret.sh npr contact-point webhook-npr
./vault/scripts/rotate-secret.sh prod grafana auth
```

## Configuration Reference

### Terraform Variables

```hcl
# variables.tf
variable "vault_address" {
  description = "The address of the Vault server"
  type        = string
}

variable "vault_token" {
  description = "Vault token (use VAULT_TOKEN env var in production)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vault_mount" {
  description = "The KV v2 secrets engine mount path"
  type        = string
  default     = "grafana"
}
```

### Environment tfvars

```hcl
# environments/npr.tfvars
grafana_url   = "http://localhost:3000"
environment   = "npr"
vault_address = "http://localhost:8200"
vault_mount   = "grafana"
```

### YAML Configuration with Vault

Enable Vault integration per-resource with `use_vault: true`:

```yaml
# Datasource with Vault credentials
datasources:
  - name: PostgreSQL
    type: postgres
    uid: postgres
    url: postgres-npr.example.com:5432
    use_vault: true  # ← Enable Vault integration
    json_data:
      database: grafana_npr
      sslmode: disable
    # secure_json_data populated from Vault

# Contact point with Vault credentials
contact_points:
  - name: webhook-critical
    type: webhook
    use_vault: true  # ← Enable Vault integration
    settings:
      url: https://alerts.example.com/webhook
      httpMethod: POST
      authorization_scheme: Bearer
      # authorization_credentials from Vault
```

## Authentication Methods

### Token Authentication (Development)

```bash
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='hvs.your-token'

terraform apply -var-file=environments/npr.tfvars
```

### AppRole Authentication (CI/CD)

Update `main.tf` for AppRole:

```hcl
provider "vault" {
  address = var.vault_address
  
  auth_login {
    path = "auth/approle/login"
    
    parameters = {
      role_id   = var.vault_role_id
      secret_id = var.vault_secret_id
    }
  }
}
```

Setup AppRole in Vault:

```bash
# Enable AppRole
vault auth enable approle

# Create role
vault write auth/approle/role/grafana-terraform \
    token_policies="grafana-terraform" \
    token_ttl=1h \
    token_max_ttl=4h

# Get role ID
vault read auth/approle/role/grafana-terraform/role-id

# Generate secret ID
vault write -f auth/approle/role/grafana-terraform/secret-id
```

### Kubernetes Authentication

```hcl
provider "vault" {
  address = var.vault_address
  
  auth_login {
    path = "auth/kubernetes/login"
    
    parameters = {
      role = "grafana-terraform"
      jwt  = file("/var/run/secrets/kubernetes.io/serviceaccount/token")
    }
  }
}
```

## CI/CD Integration

### GitHub Actions

```yaml
name: Grafana Terraform

on:
  push:
    branches: [main]
  pull_request:

env:
  TF_VERSION: '1.6.0'

jobs:
  terraform:
    runs-on: ubuntu-latest
    environment: production
    
    steps:
      - uses: actions/checkout@v4
      
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}
      
      - name: Import Vault Secrets
        uses: hashicorp/vault-action@v2
        with:
          url: ${{ secrets.VAULT_ADDR }}
          method: approle
          roleId: ${{ secrets.VAULT_ROLE_ID }}
          secretId: ${{ secrets.VAULT_SECRET_ID }}
          exportToken: true
      
      - name: Terraform Init
        run: terraform init -backend-config=backends/prod.tfbackend
      
      - name: Terraform Plan
        run: terraform plan -var-file=environments/prod.tfvars -out=tfplan
      
      - name: Terraform Apply
        if: github.ref == 'refs/heads/main'
        run: terraform apply -auto-approve tfplan
```

### GitLab CI

```yaml
stages:
  - validate
  - plan
  - apply

variables:
  TF_VERSION: "1.6.0"

.terraform_base:
  image: hashicorp/terraform:$TF_VERSION
  before_script:
    - export VAULT_ADDR=$VAULT_ADDR
    - export VAULT_TOKEN=$(vault write -field=token auth/approle/login role_id=$VAULT_ROLE_ID secret_id=$VAULT_SECRET_ID)

plan:
  extends: .terraform_base
  stage: plan
  script:
    - terraform init -backend-config=backends/prod.tfbackend
    - terraform plan -var-file=environments/prod.tfvars -out=tfplan
  artifacts:
    paths:
      - tfplan

apply:
  extends: .terraform_base
  stage: apply
  script:
    - terraform apply -auto-approve tfplan
  when: manual
  only:
    - main
```

## Security Best Practices

### 1. Secret Hygiene

```bash
#  DO: Use environment variables for tokens
export VAULT_TOKEN='hvs.xxx'

#  DON'T: Hardcode tokens in files
vault_token = "hvs.xxx"  # Never do this!
```

### 2. Vault Policy (Least Privilege)

```hcl
# vault/policies/grafana-terraform.hcl

# Read-only access to secrets
path "grafana/data/npr/*" {
  capabilities = ["read"]
}

path "grafana/data/preprod/*" {
  capabilities = ["read"]
}

path "grafana/data/prod/*" {
  capabilities = ["read"]
}

# List access for discovery
path "grafana/metadata/*" {
  capabilities = ["list", "read"]
}

# Deny access to policy management
path "sys/policy/*" {
  capabilities = ["deny"]
}
```

Apply the policy:

```bash
vault policy write grafana-terraform vault/policies/grafana-terraform.hcl
```

### 3. Token TTLs

```bash
# Create tokens with short TTLs
vault token create \
    -policy=grafana-terraform \
    -ttl=1h \
    -max-ttl=4h
```

### 4. Audit Logging

```bash
# Enable audit logging
vault audit enable file file_path=/var/log/vault_audit.log

# View recent access
tail -f /var/log/vault_audit.log | jq
```

### 5. Secret Rotation Schedule

| Secret Type | Rotation Frequency |
|-------------|-------------------|
| Grafana Admin | Quarterly |
| Datasource Credentials | Monthly |
| Webhook Tokens | Monthly |
| SSO Client Secrets | Annually |

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| `permission denied` | Token lacks policy | Check token policies: `vault token lookup` |
| `secret not found` | Wrong path or missing secret | Run `./vault/scripts/verify-secrets.sh {env}` |
| `connection refused` | Vault not running or wrong address | Verify `VAULT_ADDR` and Vault status |
| `token expired` | Token TTL exceeded | Generate new token or use auto-renewal |

### Debug Commands

```bash
# Check Vault status
vault status

# Verify token
vault token lookup

# List secrets
vault kv list grafana/npr/

# Get specific secret
vault kv get grafana/npr/grafana/auth

# Check policies
vault token capabilities grafana/data/npr/grafana/auth

# Enable debug logging
export VAULT_LOG_LEVEL=debug
```

### Terraform Debug

```bash
# Enable Terraform debug logging
TF_LOG=DEBUG terraform plan -var-file=environments/npr.tfvars 2>&1 | tee terraform.log

# Check provider configuration
terraform providers
```

## Additional Resources

- [HashiCorp Vault Documentation](https://developer.hashicorp.com/vault/docs)
- [Terraform Vault Provider](https://registry.terraform.io/providers/hashicorp/vault/latest/docs)
- [Vault KV v2 Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2)
- [Vault AppRole Authentication](https://developer.hashicorp.com/vault/docs/auth/approle)
