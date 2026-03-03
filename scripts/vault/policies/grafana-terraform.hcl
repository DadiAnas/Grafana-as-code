# Vault Policy for Grafana Terraform
# This policy grants read access to Grafana secrets

# Read access to all environment secrets
path "grafana/data/npr/*" {
  capabilities = ["read"]
}

path "grafana/data/preprod/*" {
  capabilities = ["read"]
}

path "grafana/data/prod/*" {
  capabilities = ["read"]
}

# List metadata (for discovery)
path "grafana/metadata/*" {
  capabilities = ["list", "read"]
}
