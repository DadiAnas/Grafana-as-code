# Folders Module

This module manages Grafana folders and their **granular permissions**.

## Features

- **Create folders** across multiple organizations
- **Granular permissions** per team, user, or org role
- **Zero-default permissions** — Grafana's built-in Viewer/Editor access is removed for all folders
- **Only explicit permissions apply** — folders with no `permissions` key get no access (except Org Admins)

## Zero-Default Permission Model

All folders are managed with zero-default permissions:
- Grafana's built-in Viewer/Editor role access is **removed** from every folder
- Only explicitly listed permissions (team, role, or user) apply
- Folders without `permissions` defined get **no access** except for Org Admins
- Teams are looked up using composite keys (`team_name/org_name`) to support the same team name across different orgs

## Permission Levels

| Level | Description |
|-------|-------------|
| `View` | Can view dashboards in the folder |
| `Edit` | Can edit dashboards in the folder |
| `Admin` | Full control including managing folder permissions |

## Configuration Examples

### Basic Folder (inherits org permissions)

```yaml
folders:
  - name: "My Folder"
    uid: "my-folder"
    org: "Main Organization"
    # No permissions = teams inherit their org-level access
```

### Folder with Team Permissions

```yaml
folders:
  - name: "Infrastructure"
    uid: "infrastructure"
    org: "Main Organization"
    permissions:
      - team: "SRE Team"
        permission: "Admin"    # SRE Team gets full control
      - team: "Platform Team"
        permission: "Edit"     # Platform Team can edit
      - role: "Viewer"
        permission: "View"     # Org Viewers can only view
```

### Folder with User Permissions

```yaml
folders:
  - name: "Private Dashboard"
    uid: "private"
    org: "Main Organization"
    permissions:
      - user: "admin@example.com"
        permission: "Admin"
      - team: "SRE Team"
        permission: "View"
```

### Folder with Role-based Permissions

```yaml
folders:
  - name: "Public Reports"
    uid: "public-reports"
    org: "Main Organization"
    permissions:
      - role: "Editor"
        permission: "Edit"
      - role: "Viewer"
        permission: "View"
```

## Variables

| Name | Description | Type | Required |
|------|-------------|------|----------|
| `folder_permissions` | Folder permissions configuration from YAML | `any` | No (defaults `{}`) |
| `dashboards_path` | Path to the dashboards directory for auto-discovery | `string` | Yes |
| `environment` | Current environment name | `string` | Yes |
| `org_ids` | Map of organization names to IDs | `map(number)` | No |
| `team_details` | Map of team composite keys to `{team_id, org_id}` | `map(object)` | No |
| `user_ids` | Map of user emails to IDs | `map(number)` | No |

## Outputs

| Name | Description |
|------|-------------|
| `folder_ids` | Map of folder paths to their IDs |
| `folder_uids` | Map of folder paths to their UIDs |
| `folder_org_ids` | Map of folder paths to their organization IDs |
| `folder_permissions_count` | Number of folders with permission overrides (all folders — defaults are removed) |
| `folders_with_permissions` | List of folder paths that have permissions managed (all folders) |

## How It Works

1. **Folders are created** using `grafana_folder` resource
2. **Zero-default permissions are applied** using `grafana_folder_permission` — built-in Viewer/Editor access is removed
3. **Only explicit permissions apply** — teams, roles, and users listed in `permissions` get access
4. **Auto-discovery** — folders are discovered from the dashboards directory structure
5. **Environment-specific overrides** — env config can override shared folder permissions
