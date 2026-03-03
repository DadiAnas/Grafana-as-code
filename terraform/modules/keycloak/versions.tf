terraform {
  required_version = ">= 1.0.0"

  required_providers {
    keycloak = {
      source  = "mrparkers/keycloak"
      version = "~> 4.4"
    }
  }
}
