#!/bin/bash
# Generate Grafana SSO environment variables from keycloak config
# Usage: ./generate-sso-env.sh <environment>

ENV=${1:-npr}

case $ENV in
  npr)
    KEYCLOAK_URL="https://keycloak-npr.example.com"
    GRAFANA_URL="http://localhost:3000"
    ;;
  preprod)
    KEYCLOAK_URL="https://keycloak-preprod.example.com"
    GRAFANA_URL="https://grafana-preprod.example.com"
    ;;
  prod)
    KEYCLOAK_URL="https://keycloak.example.com"
    GRAFANA_URL="https://grafana.example.com"
    ;;
  *)
    echo "Unknown environment: $ENV"
    exit 1
    ;;
esac

REALM="grafana"

cat << EOF
# Grafana SSO Environment Variables for $ENV
# Add these to your Grafana deployment

# Server
GF_SERVER_ROOT_URL=${GRAFANA_URL}

# Auth
GF_AUTH_DISABLE_LOGIN_FORM=false
GF_AUTH_SIGNOUT_REDIRECT_URL=${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/logout?redirect_uri=$(echo ${GRAFANA_URL}/login | sed 's/:/%3A/g; s/\//%2F/g')

# Generic OAuth (Keycloak)
GF_AUTH_GENERIC_OAUTH_ENABLED=true
GF_AUTH_GENERIC_OAUTH_NAME=Keycloak
GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP=true
GF_AUTH_GENERIC_OAUTH_CLIENT_ID=grafana
GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET=\${KEYCLOAK_CLIENT_SECRET}
GF_AUTH_GENERIC_OAUTH_SCOPES=openid profile email groups
GF_AUTH_GENERIC_OAUTH_AUTH_URL=${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/auth
GF_AUTH_GENERIC_OAUTH_TOKEN_URL=${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token
GF_AUTH_GENERIC_OAUTH_API_URL=${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/userinfo

# Attribute paths
GF_AUTH_GENERIC_OAUTH_LOGIN_ATTRIBUTE_PATH=preferred_username
GF_AUTH_GENERIC_OAUTH_EMAIL_ATTRIBUTE_PATH=email
GF_AUTH_GENERIC_OAUTH_NAME_ATTRIBUTE_PATH=name
GF_AUTH_GENERIC_OAUTH_GROUPS_ATTRIBUTE_PATH=groups

# Role mapping
GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH=contains(groups[*], 'grafana-admin') && 'Admin' || contains(groups[*], 'grafana-editor') && 'Editor' || 'Viewer'
GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_STRICT=false
GF_AUTH_GENERIC_OAUTH_ALLOW_ASSIGN_GRAFANA_ADMIN=true

# Org mapping
GF_AUTH_GENERIC_OAUTH_ORG_ATTRIBUTE_PATH=org
GF_AUTH_GENERIC_OAUTH_ORG_MAPPING=platform-team:Platform Team:Editor,platform-admins:Platform Team:Admin,app-team:Application Team:Editor,app-admins:Application Team:Admin

EOF
