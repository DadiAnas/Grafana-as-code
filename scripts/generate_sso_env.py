#!/usr/bin/env python3
"""
Generate SSO Environment Variables — Output Grafana SSO config for a given environment.

Usage:
    python scripts/generate_sso_env.py <environment>
    python scripts/generate_sso_env.py npr
    python scripts/generate_sso_env.py preprod
    python scripts/generate_sso_env.py prod
"""
from __future__ import annotations

import argparse
import sys
from urllib.parse import quote


class Colors:
    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    BLUE = "\033[0;34m"
    CYAN = "\033[0;36m"
    DIM = "\033[2m"
    BOLD = "\033[1m"
    NC = "\033[0m"


ENV_CONFIG: dict[str, dict[str, str]] = {
    "npr": {
        "keycloak_url": "https://keycloak-npr.example.com",
        "grafana_url": "http://localhost:3000",
    },
    "preprod": {
        "keycloak_url": "https://keycloak-preprod.example.com",
        "grafana_url": "https://grafana-preprod.example.com",
    },
    "prod": {
        "keycloak_url": "https://keycloak.example.com",
        "grafana_url": "https://grafana.example.com",
    },
}

REALM = "grafana"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate Grafana SSO environment variables from keycloak config"
    )
    parser.add_argument(
        "env",
        nargs="?",
        default="npr",
        choices=list(ENV_CONFIG.keys()),
        help="Environment name (default: npr)",
    )
    args = parser.parse_args()

    env: str = args.env

    if env not in ENV_CONFIG:
        print(f"Unknown environment: {env}", file=sys.stderr)
        sys.exit(1)

    cfg = ENV_CONFIG[env]
    keycloak_url = cfg["keycloak_url"]
    grafana_url = cfg["grafana_url"]

    redirect_uri = quote(f"{grafana_url}/login", safe="")

    print(f"# Grafana SSO Environment Variables for {env}")
    print("# Add these to your Grafana deployment")
    print()
    print("# Server")
    print(f"GF_SERVER_ROOT_URL={grafana_url}")
    print()
    print("# Auth")
    print("GF_AUTH_DISABLE_LOGIN_FORM=false")
    print(
        f"GF_AUTH_SIGNOUT_REDIRECT_URL={keycloak_url}/realms/{REALM}"
        f"/protocol/openid-connect/logout?redirect_uri={redirect_uri}"
    )
    print()
    print("# Generic OAuth (Keycloak)")
    print("GF_AUTH_GENERIC_OAUTH_ENABLED=true")
    print("GF_AUTH_GENERIC_OAUTH_NAME=Keycloak")
    print("GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP=true")
    print("GF_AUTH_GENERIC_OAUTH_CLIENT_ID=grafana")
    print("GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET=${KEYCLOAK_CLIENT_SECRET}")
    print("GF_AUTH_GENERIC_OAUTH_SCOPES=openid profile email groups")
    print(
        f"GF_AUTH_GENERIC_OAUTH_AUTH_URL={keycloak_url}/realms/{REALM}"
        "/protocol/openid-connect/auth"
    )
    print(
        f"GF_AUTH_GENERIC_OAUTH_TOKEN_URL={keycloak_url}/realms/{REALM}"
        "/protocol/openid-connect/token"
    )
    print(
        f"GF_AUTH_GENERIC_OAUTH_API_URL={keycloak_url}/realms/{REALM}"
        "/protocol/openid-connect/userinfo"
    )
    print()
    print("# Attribute paths")
    print("GF_AUTH_GENERIC_OAUTH_LOGIN_ATTRIBUTE_PATH=preferred_username")
    print("GF_AUTH_GENERIC_OAUTH_EMAIL_ATTRIBUTE_PATH=email")
    print("GF_AUTH_GENERIC_OAUTH_NAME_ATTRIBUTE_PATH=name")
    print("GF_AUTH_GENERIC_OAUTH_GROUPS_ATTRIBUTE_PATH=groups")
    print()
    print("# Role mapping")
    print(
        "GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH="
        "contains(groups[*], 'grafana-admin') && 'Admin' || "
        "contains(groups[*], 'grafana-editor') && 'Editor' || 'Viewer'"
    )
    print("GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_STRICT=false")
    print("GF_AUTH_GENERIC_OAUTH_ALLOW_ASSIGN_GRAFANA_ADMIN=true")
    print()
    print("# Org mapping")
    print("GF_AUTH_GENERIC_OAUTH_ORG_ATTRIBUTE_PATH=org")
    print(
        "GF_AUTH_GENERIC_OAUTH_ORG_MAPPING="
        "platform-team:Platform Team:Editor,"
        "platform-admins:Platform Team:Admin,"
        "app-team:Application Team:Editor,"
        "app-admins:Application Team:Admin"
    )
    print()


if __name__ == "__main__":
    main()
