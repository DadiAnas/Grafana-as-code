# Keycloak SSO Integration Guide

This guide covers setting up Keycloak as the identity provider for Grafana with organization and role mapping.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Keycloak Configuration](#keycloak-configuration)
- [Grafana Configuration](#grafana-configuration)
- [Organization Mapping](#organization-mapping)
- [Role Mapping](#role-mapping)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)

## Overview

This project uses Keycloak for SSO authentication with the following features:

- **Single Sign-On**: Users authenticate once via Keycloak
- **Organization Mapping**: Keycloak groups map to Grafana organizations
- **Role Mapping**: Keycloak roles/groups determine Grafana permissions
- **Multi-Organization Access**: Users can belong to multiple organizations
- **Public Organization**: All users get Viewer access to shared dashboards

## Prerequisites

- Keycloak server (v18+ recommended)
- Admin access to Keycloak realm
- Network connectivity between Grafana and Keycloak
- SSL certificates for production environments

## Keycloak Configuration

### 1. Create Realm (if needed)

```bash
# Via Keycloak Admin API
curl -X POST "https://keycloak.example.com/admin/realms" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"realm": "grafana", "enabled": true}'
```

Or via Keycloak Admin Console:
1. Login to Keycloak Admin Console
2. Click "Create Realm"
3. Name: `grafana`
4. Click "Create"

### 2. Create Client for Each Environment

#### NPR Client

| Setting | Value |
|---------|-------|
| Client ID | `grafana-npr` |
| Client Protocol | `openid-connect` |
| Access Type | `confidential` |
| Root URL | `http://localhost:3000` |
| Valid Redirect URIs | `http://localhost:3000/*` |
| Web Origins | `http://localhost:3000` |

#### PreProd Client

| Setting | Value |
|---------|-------|
| Client ID | `grafana-preprod` |
| Root URL | `https://grafana-preprod.example.com` |
| Valid Redirect URIs | `https://grafana-preprod.example.com/*` |

#### Prod Client

| Setting | Value |
|---------|-------|
| Client ID | `grafana-prod` |
| Root URL | `https://grafana.example.com` |
| Valid Redirect URIs | `https://grafana.example.com/*` |

### 3. Configure Client Scopes

Create a mapper to include groups in the token:

1. Go to Client → `grafana-{env}` → Client Scopes
2. Click on `grafana-{env}-dedicated`
3. Add mapper:
   - Mapper type: `Group Membership`
   - Name: `groups`
   - Token Claim Name: `groups`
   - Full group path: `OFF`
   - Add to ID token: `ON`
   - Add to access token: `ON`
   - Add to userinfo: `ON`

### 4. Create Groups

Create the following groups in Keycloak:

```
/grafana-users          # All Grafana users
/platform-team          # Platform team members
/platform-admins        # Platform team admins
/app-team              # Application team members
/app-admins            # Application team admins
/bi-team               # Business Intelligence team
/bi-admins             # BI team admins
/grafana-admin         # Grafana super admins
/grafana-editor        # Global editors
```

### 5. Assign Users to Groups

1. Go to Users → Select user
2. Click "Groups" tab
3. Join appropriate groups

## Grafana Configuration

### Configuration Files

SSO is configured via two files:

1. **Shared settings**: `config/shared/sso/keycloak.yaml`
2. **Environment-specific**: `config/{env}/grafana-sso.ini`

### grafana-sso.ini (Per Environment)

```ini
# config/npr/grafana-sso.ini

[auth.generic_oauth]
enabled = true
name = Keycloak
allow_sign_up = true
auto_login = false

# Keycloak endpoints
client_id = grafana-npr
client_secret = ${KEYCLOAK_CLIENT_SECRET}
scopes = openid profile email groups
auth_url = https://keycloak-npr.example.com/realms/grafana/protocol/openid-connect/auth
token_url = https://keycloak-npr.example.com/realms/grafana/protocol/openid-connect/token
api_url = https://keycloak-npr.example.com/realms/grafana/protocol/openid-connect/userinfo

# Attribute mapping
login_attribute_path = preferred_username
email_attribute_path = email
name_attribute_path = name
groups_attribute_path = groups

# Role mapping
role_attribute_path = contains(groups[*], 'grafana-admin') && 'Admin' || contains(groups[*], 'grafana-editor') && 'Editor' || 'Viewer'

# Organization mapping
org_mapping = platform-team:Platform Team:Editor, platform-admins:Platform Team:Admin, app-team:Application Team:Editor, bi-team:Business Intelligence:Viewer

# Allow users in multiple orgs
allow_assign_grafana_admin = true
```

### Storing Client Secret in Vault

```bash
# Store the Keycloak client secret in Vault
vault kv put grafana/npr/sso/keycloak \
    client_id="grafana-npr" \
    client_secret="your-client-secret-here"
```

## Organization Mapping

### Mapping Configuration

The `keycloak.yaml` defines how Keycloak groups map to Grafana organizations:

```yaml
# config/shared/sso/keycloak.yaml
org_mapping:
  mappings:
    # Platform Team
    - keycloak_group: "platform-team"
      grafana_org: "Platform Team"
      role: "Editor"
    
    - keycloak_group: "platform-admins"
      grafana_org: "Platform Team"
      role: "Admin"
    
    # Application Team
    - keycloak_group: "app-team"
      grafana_org: "Application Team"
      role: "Editor"
    
    - keycloak_group: "app-admins"
      grafana_org: "Application Team"
      role: "Admin"
    
    # Business Intelligence
    - keycloak_group: "bi-team"
      grafana_org: "Business Intelligence"
      role: "Viewer"
    
    - keycloak_group: "bi-admins"
      grafana_org: "Business Intelligence"
      role: "Admin"
    
    # Public Organization - Everyone gets Viewer access
    - keycloak_group: "platform-team"
      grafana_org: "Public"
      role: "Viewer"
    
    - keycloak_group: "app-team"
      grafana_org: "Public"
      role: "Viewer"
    
    - keycloak_group: "bi-team"
      grafana_org: "Public"
      role: "Viewer"
    
    - keycloak_group: "grafana-users"
      grafana_org: "Public"
      role: "Viewer"
```

### Mapping Matrix

| Keycloak Group | Platform Team | Application Team | BI | Public |
|---------------|---------------|------------------|-----|--------|
| platform-team | Editor | - | - | Viewer |
| platform-admins | Admin | - | - | Viewer |
| app-team | - | Editor | - | Viewer |
| app-admins | - | Admin | - | Viewer |
| bi-team | - | - | Viewer | Viewer |
| bi-admins | - | - | Admin | Viewer |
| grafana-users | - | - | - | Viewer |

## Role Mapping

### Role Hierarchy

| Grafana Role | Permissions |
|-------------|-------------|
| **Admin** | Full control of org (manage users, datasources, folders) |
| **Editor** | Create/edit dashboards, alerts, playlists |
| **Viewer** | View dashboards and alerts only |

### JMESPath Expression

The role is determined using a JMESPath expression:

```
contains(groups[*], 'grafana-admin') && 'Admin' || 
contains(groups[*], 'grafana-editor') && 'Editor' || 
'Viewer'
```

This means:
1. If user is in `grafana-admin` group → Admin role
2. Else if user is in `grafana-editor` group → Editor role
3. Else → Viewer role

### Global vs Organization Roles

- **Global Role**: Set by `role_attribute_path` - applies across Grafana
- **Organization Role**: Set by `org_mapping` - specific to each organization

A user can be:
- Admin in "Platform Team" organization
- Viewer in "Public" organization
- Editor globally (via `grafana-editor` group)

## Testing

### 1. Verify Keycloak Token

```bash
# Get a token from Keycloak
TOKEN=$(curl -s -X POST \
  "https://keycloak.example.com/realms/grafana/protocol/openid-connect/token" \
  -d "client_id=grafana-npr" \
  -d "client_secret=your-secret" \
  -d "username=testuser" \
  -d "password=testpass" \
  -d "grant_type=password" | jq -r '.access_token')

# Decode and inspect the token
echo $TOKEN | cut -d'.' -f2 | base64 -d | jq
```

Expected claims:
```json
{
  "preferred_username": "testuser",
  "email": "testuser@example.com",
  "groups": ["platform-team", "grafana-users"]
}
```

### 2. Test SSO Login

1. Navigate to Grafana login page
2. Click "Sign in with Keycloak"
3. Authenticate with Keycloak credentials
4. Verify correct organization assignment

### 3. Verify Organization Access

```bash
# Check user's organizations via Grafana API
curl -s "http://localhost:3000/api/user/orgs" \
  -H "Authorization: Bearer $GRAFANA_TOKEN" | jq
```

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "Invalid redirect URI" | Mismatch in Keycloak client config | Verify Valid Redirect URIs include Grafana URL |
| User not assigned to org | Group not mapped | Check `org_mapping` configuration |
| Wrong role assigned | JMESPath expression issue | Test expression with sample token |
| Groups not in token | Missing mapper | Add Group Membership mapper to client |

### Debug Logging

Enable OAuth debug logging in Grafana:

```ini
[log]
level = debug
filters = oauth:debug
```

### Verify Token Claims

```bash
# Enable Grafana to log token claims
[auth.generic_oauth]
debug = true
```

Check Grafana logs for:
```
lvl=dbug msg="Received OAuth token" ...
lvl=dbug msg="Extracted groups from token" groups="[platform-team, grafana-users]"
```

### Test JMESPath Expression

Use the `jp` CLI tool to test expressions:

```bash
# Install jp
go install github.com/jmespath/jp/cmd/jp@latest

# Test expression
echo '{"groups": ["platform-team", "grafana-users"]}' | \
  jp "contains(groups[*], 'grafana-admin') && 'Admin' || 'Viewer'"
# Output: "Viewer"
```

## Security Considerations

1. **Use HTTPS**: Always use HTTPS in production
2. **Rotate Secrets**: Rotate client secrets regularly
3. **Limit Scopes**: Only request necessary scopes
4. **Audit Logs**: Enable Keycloak event logging
5. **Session Timeout**: Configure appropriate session timeouts

## Team Sync (Keycloak → Grafana)

After SSO maps users to organizations, team sync maps Keycloak group membership to Grafana teams.

### Grafana OSS

Run the standalone sync script:

```bash
make team-sync
```

The script reads `external_groups` from `teams.yaml`, queries Keycloak for group members, and adds matching Grafana users to the corresponding teams via the Grafana API. It is **one-way** (Keycloak is the source of truth) and does not auto-add users to organizations — they must log in via SSO first.

### Grafana Enterprise / Cloud

Set `enable_team_sync = true` in your tfvars:

```hcl
enable_team_sync = true
```

This enables the `grafana_team_external_group` Terraform resource, which natively maps `external_groups` to Grafana teams without a separate script.

### Configuration

Define `external_groups` on each team in `teams.yaml`:

```yaml
teams:
  - name: "Backend Team"
    org: "Main Org."
    external_groups:
      - "grafana-developers"

  - name: "grafana-viewers"
    org: "Main Org."
    external_groups:
      - "grafana-viewers"

  - name: "grafana-viewers"
    org: "Public"
    external_groups:
      - "grafana-viewers"
```

> **Note:** The same team name can exist in multiple organizations. Each is synced independently.

## Additional Resources

- [Grafana OAuth Documentation](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-authentication/generic-oauth/)
- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [JMESPath Specification](https://jmespath.org/)
