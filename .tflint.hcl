# =============================================================================
# TFLINT CONFIGURATION
# =============================================================================
# Run: tflint --init && tflint
# Or:  make lint
# =============================================================================

config {
  # Enable module inspection
  call_module_type = "local"
}

# Terraform rules plugin
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# =============================================================================
# CUSTOM RULES
# =============================================================================

# Enforce consistent naming convention
rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

# Ensure all variables have descriptions
rule "terraform_documented_variables" {
  enabled = true
}

# Ensure all outputs have descriptions
rule "terraform_documented_outputs" {
  enabled = true
}

# Warn on unused variables
rule "terraform_unused_declarations" {
  enabled = true
}

# Enforce standard module structure
rule "terraform_standard_module_structure" {
  enabled = true
}
