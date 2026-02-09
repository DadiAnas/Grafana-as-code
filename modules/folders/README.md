# Folders Module

This module manages Grafana folders and their **granular permissions**.

## Features

- **Create folders** across multiple organizations
- **Granular permissions** per team, user, or org role
- **Permission inheritance** - teams inherit org-level access by default
- **Override when needed** - specify folder-specific permissions

## Permission Inheritance

By default, teams inherit their **organization-level role permissions**:
- If a team is an Editor in an org, they get Edit access to all folders
- If a team is a Viewer in an org, they get View access to all folders

You only need to define `permissions` when you want to **override the defaults**.

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
| `folders` | Folders configuration from YAML | `any` | Yes |
| `org_ids` | Map of organization names to IDs | `map(number)` | No |
| `team_ids` | Map of team names to numeric IDs | `map(number)` | No |
| `user_ids` | Map of user emails to IDs | `map(number)` | No |

## Outputs

| Name | Description |
|------|-------------|
| `folder_ids` | Map of folder UIDs to their full IDs |
| `folder_uids` | Map of folder UIDs (for compatibility) |
| `folder_org_ids` | Map of folder UIDs to organization IDs |
| `folder_permissions_count` | Count of folders with explicit permissions |
| `folders_with_permissions` | List of folder UIDs with explicit permissions |

## How It Works

1. **Folders are created first** using `grafana_folder` resource
2. **Permissions are applied** using `grafana_folder_permission` resource
3. **Only explicit permissions are managed** - folders without `permissions` defined inherit defaults
4. **Environment-specific overrides** - NPR/PreProd/Prod can override shared folder permissions
