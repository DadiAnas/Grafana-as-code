# Configuration Reference

This document provides a complete reference for all YAML configuration files used in this project.

## Table of Contents

- [Configuration Merge Pattern](#configuration-merge-pattern)
- [Organizations](#organizations)
- [Folders](#folders)
- [Datasources](#datasources)
- [Teams](#teams)
- [Service Accounts](#service-accounts)
- [Alert Rules](#alert-rules)
- [Contact Points](#contact-points)
- [Notification Policies](#notification-policies)
- [Mute Timings](#mute-timings)

---

## Configuration Merge Pattern

All resources follow a **shared + environment-specific** pattern where environment configs override shared ones.
All per-org resources are stored in **subdirectories named after the Grafana organization**.

| Resource | Shared Location | Env Location | Merge Key |
|----------|----------------|--------------|-----------|
| Datasources | `base/datasources/_default/datasources.yaml` | `envs/{env}/datasources/{Org}/datasources.yaml` | `orgId:uid` |
| Organizations | `base/organizations.yaml` | `envs/{env}/organizations.yaml` | `name` |
| Folders | `base/folders/_default/folders.yaml` | `envs/{env}/folders/{Org}/folders.yaml` | `orgId:uid` |
| Teams | `base/teams/_default/teams.yaml` | `envs/{env}/teams/{Org}/teams.yaml` | `name/orgId` |
| Service Accounts | `base/service_accounts/_default/service_accounts.yaml` | `envs/{env}/service_accounts/{Org}/service_accounts.yaml` | `orgId:name` |
| Alert Rules | `base/alerting/_default/alert_rules.yaml` | `envs/{env}/alerting/{Org}/alert_rules.yaml` | `orgId:folder-name` |
| Contact Points | `base/alerting/_default/contact_points.yaml` | `envs/{env}/alerting/{Org}/contact_points.yaml` | `orgId:name` |
| Notification Policies | `base/alerting/_default/notification_policies.yaml` | `envs/{env}/alerting/{Org}/notification_policies.yaml` | `orgId` |
| Dashboards | `base/dashboards/{folder}/` | `envs/{env}/dashboards/{folder}/` | filename |

**Environment-specific configs override shared configs** with the same merge key.

> **Note:** Resources use `orgId` (numeric Grafana org ID) rather than `org` (name string). The `import_from_grafana.py` script automatically fills in the correct `orgId` for each organization when importing.

---

## Organizations

**File**: `base/organizations.yaml`
**Env Override**: `envs/{env}/organizations.yaml`

Defines Grafana organizations for multi-tenancy.

```yaml
organizations:
  - name: "Organization Name"     # Required: Display name
    id: 1                         # Optional: Explicit ID (for default org)
    description: "Description"    # Optional: Organization description
    admins:                       # Optional: Admin users
      - "admin@example.com"
    editors:                      # Optional: Editor users
      - "editor@example.com"
    viewers:                      # Optional: Viewer users
      - "viewer@example.com"
```

### Example

```yaml
organizations:
  - name: "Main Organization"
    id: 1

  - name: "Public"
    description: "Shared dashboards for all users"
    admins: []
    editors: []
    viewers: []

  - name: "Platform Team"
    admins:
      - "platform-admin@example.com"
    editors:
      - "platform-dev@example.com"
```

---

## Folders

**File**: `base/folders/_default/folders.yaml`
**Env Override**: `envs/{env}/folders/{Org Name}/folders.yaml`

Defines the folder structure for organizing dashboards. Each file is placed in the subdirectory matching the Grafana org name, using `orgId` to scope it.

```yaml
folders:
  - title: "Folder Name"           # Required: Display name
    uid: "folder-uid"             # Required: Unique identifier
    orgId: 1                      # Required: Numeric org ID
    permissions:                   # Optional: Access control (see below)
      - team: "Team Name"         # Grant access to a team
        permission: "View"        # View, Edit, or Admin
      - role: "Viewer"            # Grant access to an org role
        permission: "View"
```

### Folder Permissions

By default, **all folders** are managed with zero-default permissions — Grafana's built-in Viewer/Editor access is removed. Only explicitly listed permissions apply. This ensures team-based access control:

- Folders with `permissions: [...]` get only those permissions
- Folders with `permissions: []` or no permissions key get **no access** (except Org Admins)
- Permission values: `View`, `Edit`, `Admin`
- Permission targets: `team` (team name), `role` (Viewer/Editor), `user` (user ID)

> **Note:** Teams referenced in permissions must exist in the same organization as the folder. The team is looked up using a composite key (`team_name/org_name`) to support teams with the same name across different orgs.

### Example

```yaml
# envs/prod/folders/Main Organization/folders.yaml
folders:
  - title: "Infrastructure"
    uid: "infrastructure"
    orgId: 1
    permissions:
      - team: "SRE Team"
        permission: "Edit"
      - team: "grafana-viewers"
        permission: "View"

  - title: "Applications"
    uid: "applications"
    orgId: 1
    permissions: []               # No access except Org Admins

# envs/prod/folders/Platform Team/folders.yaml
folders:
  - title: "Kubernetes"
    uid: "platform-kubernetes"
    orgId: 3
    permissions:
      - role: "Viewer"
        permission: "View"
```

---

## Datasources

**Files**:
- Shared: `base/datasources/_default/datasources.yaml`
- Environment: `envs/{env}/datasources/{Org Name}/datasources.yaml`

Defines data sources with full parameter support. Environment-specific datasources override shared ones with the same `orgId:uid` composite key.

### All Parameters

```yaml
datasources:
  - name: "Datasource Name"        # Required: Display name
    type: "datasource-type"        # Required: prometheus, loki, postgres, etc.
    uid: "unique-id"               # Required: Unique identifier
    url: "http://host:port"        # Required: Connection URL
    orgId: 1                       # Required: Numeric org ID
    is_default: true/false         # Optional: Default datasource
    access_mode: "proxy"           # Optional: proxy or direct
    basic_auth_enabled: true/false # Optional: Enable basic auth
    basic_auth_username: "user"    # Optional: Basic auth username
    database_name: "mydb"          # Optional: Database name (SQL datasources)
    username: "dbuser"             # Optional: Database/API username
    use_vault: true/false          # Optional: Fetch secrets from Vault
    http_headers:                  # Optional: Custom HTTP headers
      X-Custom-Header: "value"
      Authorization: "Bearer token"
    json_data:                     # Optional: Type-specific settings
      key: value
    secure_json_data:              # Optional: Sensitive settings (or use Vault)
      password: "secret"
```

### Datasource Types & json_data Reference

| Type | Description | Common json_data Keys |
|------|-------------|----------------------|
| `prometheus` | Prometheus metrics | `httpMethod`, `timeInterval`, `queryTimeout`, `customQueryParameters`, `exemplarTraceIdDestinations`, `incrementalQuerying` |
| `loki` | Loki logs | `maxLines`, `derivedFields`, `alertmanager` |
| `postgres` | PostgreSQL | `postgresVersion`, `sslmode`, `connMaxLifetime`, `maxIdleConns`, `maxOpenConns`, `timescaledb` |
| `mysql` | MySQL | `maxOpenConns`, `maxIdleConns`, `connMaxLifetime` |
| `elasticsearch` | Elasticsearch | `esVersion`, `timeField`, `logMessageField`, `logLevelField`, `maxConcurrentShardRequests` |
| `influxdb` | InfluxDB | `version`, `organization`, `defaultBucket`, `httpMode` |
| `tempo` | Tempo traces | `tracesToLogs`, `tracesToMetrics`, `nodeGraph`, `lokiSearch` |
| `jaeger` | Jaeger traces | `nodeGraph`, `tracesToLogs` |
| `graphite` | Graphite | `graphiteVersion`, `graphiteType` |
| `cloudwatch` | AWS CloudWatch | `authType`, `assumeRoleArn`, `externalId`, `defaultRegion`, `customMetricsNamespaces` |
| `opentsdb` | OpenTSDB | `tsdbVersion`, `tsdbResolution` |

### Examples

#### Prometheus with Custom Headers

```yaml
# envs/prod/datasources/Main Organization/datasources.yaml
datasources:
  - name: "My Prometheus"
    type: "prometheus"
    uid: "prometheus-main"
    url: "http://prometheus:9090"
    orgId: 1
    is_default: true
    http_headers:
      X-Custom-Header: "my-value"
    json_data:
      httpMethod: "POST"
      timeInterval: "15s"
      queryTimeout: "60s"
```

#### PostgreSQL with Vault

```yaml
datasources:
  - name: "PostgreSQL"
    type: "postgres"
    uid: "postgres"
    url: "postgres.example.com:5432"
    orgId: 1
    use_vault: true
    database_name: "app_db"
    username: "grafana_reader"
    json_data:
      sslmode: "require"
      maxOpenConns: 10
      maxIdleConns: 5
```

#### Elasticsearch

```yaml
- name: "Elasticsearch"
  type: "elasticsearch"
  uid: "elasticsearch"
  url: "http://elasticsearch:9200"
  json_data:
    esVersion: "8.0.0"
    timeField: "@timestamp"
    logMessageField: "message"
    logLevelField: "level"
```

---

## Teams

**File**: `base/teams/_default/teams.yaml`
**Env Override**: `envs/{env}/teams/{Org Name}/teams.yaml`

Defines teams for access control. Teams use a composite key (`name/orgId`) internally, so the same team name can exist in different organizations.

```yaml
teams:
  - name: "Team Name"             # Required: Display name
    orgId: 1                      # Required: Numeric org ID
    email: "team@example.com"     # Optional: Team email
    external_groups:              # Optional: IdP groups for team sync
      - "keycloak-group-name"
    members:                      # Optional: Team members
      - email: "user@example.com"
        role: "Member"            # Member or Admin
```

### Team Sync

Team membership can be synchronized from an identity provider (Keycloak, Okta, etc.):

- **Grafana Enterprise/Cloud**: Set `enable_team_sync = true` in tfvars. Uses the `grafana_team_external_group` resource to map `external_groups` automatically.
- **Grafana OSS**: Run `make team-sync` to sync Keycloak group membership to Grafana teams via API. This is a standalone operation — not run by Terraform.

The `external_groups` field specifies which IdP groups map to each Grafana team. Terraform ignores `members` changes (`lifecycle { ignore_changes = [members] }`) so that team-sync membership is preserved across applies.

> **Note:** For OSS team sync, users must log in via SSO at least once before they can be added to teams. The sync script warns if a user hasn't logged in yet.

### Same Team in Multiple Orgs

Teams are identified by a composite key `name/org`. This allows the same team name in different organizations:

```yaml
teams:
  - name: "grafana-viewers"
    org: "Main Org."
    external_groups: ["grafana-viewers"]

  - name: "grafana-viewers"
    org: "Public"
    external_groups: ["grafana-viewers"]
```

These create two separate teams, each synced from the same Keycloak group but scoped to their respective orgs.

### Example

```yaml
# envs/prod/teams/Platform Team/teams.yaml
teams:
  - name: "Platform Engineering"
    orgId: 3
    email: "platform@example.com"
    external_groups:
      - "grafana-platform-team"
    members:
      - email: "alice@example.com"
        role: "Admin"
      - email: "bob@example.com"
        role: "Member"

# envs/prod/teams/Main Organization/teams.yaml
teams:
  - name: "SRE"
    orgId: 1
    external_groups:
      - "grafana-sre"
    members:
      - email: "sre@example.com"
        role: "Admin"
```

---

## Service Accounts

**File**: `base/service_accounts/_default/service_accounts.yaml`
**Env Override**: `envs/{env}/service_accounts/{Org Name}/service_accounts.yaml`

Defines service accounts for API access.

```yaml
service_accounts:
  - name: "Account Name"          # Required: Display name
    orgId: 1                      # Required: Numeric org ID
    role: "Viewer"                # Required: Viewer, Editor, or Admin
    is_disabled: false            # Optional: Disable account
    tokens:                       # Optional: API tokens
      - name: "token-name"
        seconds_to_live: 31536000 # Optional: TTL in seconds (0 = no expiry)
```

### Example

```yaml
# envs/prod/service_accounts/Main Organization/service_accounts.yaml
service_accounts:
  - name: "ci-cd-deployer"
    orgId: 1
    role: "Editor"
    tokens:
      - name: "github-actions"
        seconds_to_live: 31536000  # 1 year

  - name: "monitoring-readonly"
    orgId: 1
    role: "Viewer"
    tokens:
      - name: "prometheus-scraper"
        seconds_to_live: 0         # No expiry
```

---

## Alert Rules

**Files**:
- Shared: `base/alerting/_default/alert_rules.yaml`
- Environment: `envs/{env}/alerting/{Org Name}/alert_rules.yaml`

Uses **Grafana's native YAML export format** with `orgId` (numeric) to scope rules to the correct organization.

### Format Overview

```yaml
apiVersion: 1

groups:
  - orgId: 1                    # Numeric org ID
    name: GroupName             # Rule group name
    folder: folder-uid          # Parent folder UID
    interval: 1m                # Evaluation interval
    rules:
      - uid: unique-rule-id     # Optional: Rule UID
        title: Alert Title      # Display name
        condition: C            # Condition reference
        for: 5m                 # Pending duration
        noDataState: NoData     # NoData, OK, Alerting, KeepLast
        execErrState: Error     # Error, OK, Alerting, KeepLast
        isPaused: false         # Pause evaluation
        annotations:
          summary: "..."
          description: "..."
        labels:
          severity: critical
        data:
          - refId: A
            datasourceUid: prometheus
            relativeTimeRange:
              from: 600
              to: 0
            model:
              expr: "your_query_here"
```

### Complete Example

```yaml
# envs/prod/alerting/Platform Team/alert_rules.yaml
apiVersion: 1

groups:
  - orgId: 3
    name: Infrastructure
    folder: platform-alerts
    interval: 1m
    rules:
      - uid: high-cpu-usage
        title: High CPU Usage
        condition: C
        data:
          - refId: A
            relativeTimeRange:
              from: 600
              to: 0
            datasourceUid: prometheus
            model:
              expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
              intervalMs: 1000
              maxDataPoints: 43200
          - refId: B
            relativeTimeRange:
              from: 600
              to: 0
            datasourceUid: __expr__
            model:
              expression: A
              intervalMs: 1000
              maxDataPoints: 43200
              reducer: mean
              type: reduce
          - refId: C
            relativeTimeRange:
              from: 600
              to: 0
            datasourceUid: __expr__
            model:
              conditions:
                - evaluator:
                    params:
                      - 80
                    type: gt
              expression: B
              intervalMs: 1000
              maxDataPoints: 43200
              type: threshold
        noDataState: OK
        execErrState: Alerting
        for: 5m
        annotations:
          summary: High CPU usage detected
          description: CPU usage is above 80% for more than 5 minutes
          runbook_url: https://wiki.example.com/runbooks/high-cpu
        labels:
          severity: warning
          team: platform
        isPaused: false
```

### Exporting from Grafana

1. Go to **Alerting > Alert rules** in Grafana
2. Click the export button (download icon)
3. Select **YAML** format
4. The export already uses `orgId` — save directly to `envs/<env>/alerting/<Org Name>/alert_rules.yaml`


### State Handling Options

| Parameter | Values | Description |
|-----------|--------|-------------|
| `no_data_state` | `NoData`, `OK`, `Alerting`, `KeepLast` | State when query returns no data |
| `exec_err_state` | `Error`, `OK`, `Alerting`, `KeepLast` | State when query execution fails |

### Example with All Parameters (Legacy Flat Format)

> **Note:** The above Grafana native format (with `groups:` and `rules:`) is the recommended format. The flat format below is an alternative supported by the module's auto-conversion logic, but using the native format is preferred.

```yaml
alert_rules:
  - name: "High CPU Usage"
    folder: "alerts"
    org: "Main Organization"
    rule_group: "Infrastructure"
    condition: "C"
    for: "5m"
    interval_seconds: 60
    no_data_state: "OK"
    exec_err_state: "Alerting"
    is_paused: false
    annotations:
      summary: "CPU usage above 80%"
      description: "Instance {{ $labels.instance }} has high CPU"
      runbook_url: "https://wiki.example.com/runbooks/high-cpu"
    labels:
      severity: "warning"
      team: "platform"
    data:
      - ref_id: "A"
        datasource_uid: "prometheus"
        relative_time_range:
          from: 600
          to: 0
        model:
          expr: "100 - (avg by(instance) (irate(node_cpu_seconds_total{mode='idle'}[5m])) * 100)"
      - ref_id: "B"
        datasource_uid: "__expr__"
        model:
          type: "reduce"
          expression: "A"
          reducer: "mean"
      - ref_id: "C"
        datasource_uid: "__expr__"
        model:
          type: "threshold"
          expression: "B"
          conditions:
            - evaluator:
                type: "gt"
                params: [80]
```

---

## Contact Points

**Files**:
- Shared: `base/alerting/contact_points.yaml`
- Environment: `envs/{env}/alerting/contact_points.yaml`

Defines notification channels with support for 20+ contact point types.

### Supported Contact Point Types

| Type | Description |
|------|-------------|
| `email` | Email notifications |
| `webhook` | Generic HTTP webhook |
| `slack` | Slack notifications |
| `pagerduty` | PagerDuty incidents |
| `opsgenie` | Opsgenie alerts |
| `discord` | Discord notifications |
| `telegram` | Telegram messages |
| `teams` | Microsoft Teams |
| `googlechat` | Google Chat |
| `victorops` | Splunk On-Call (VictorOps) |
| `pushover` | Pushover notifications |
| `sns` | AWS SNS |
| `sensugo` | Sensu Go |
| `threema` | Threema messages |
| `webex` | Cisco Webex |
| `line` | LINE notifications |
| `kafka` | Kafka events |
| `oncall` | Grafana OnCall |
| `alertmanager` | Alertmanager integration |
| `dingding` | DingTalk |
| `wecom` | WeChat Work |

### Base Template

```yaml
contactPoints:
  - name: "Contact Name"          # Required: Display name
    org: "Organization Name"      # Required: Parent organization
    receivers:                     # Required: Array of receivers
      - type: "contact-type"      # Required: Contact type from list above
        settings:                  # Required: Type-specific settings
          # See type-specific settings below
        disableResolveMessage: false  # Optional: Suppress resolve notifications
```

### Email Settings

```yaml
# envs/prod/alerting/Main Organization/contact_points.yaml
contactPoints:
  - name: "email-alerts"
    orgId: 1
    receivers:
      - type: "email"
        settings:
          addresses: "team@example.com;oncall@example.com"
          singleEmail: true
          subject: "[{{ .Status }}] {{ .CommonLabels.alertname }}"
          message: |
            {{ range .Alerts }}
            Alert: {{ .Labels.alertname }}
            Status: {{ .Status }}
            {{ end }}
        disableResolveMessage: false
```

### Webhook Settings

```yaml
contactPoints:
  - name: "webhook-critical"
    orgId: 1
    receivers:
      - type: "webhook"
        settings:
          url: "https://alerts.example.com/webhook"
          httpMethod: "POST"
          # authorization_credentials: "vault:webhook-myenv"  # Fetch from Vault
        disableResolveMessage: false
```

### Slack Settings

```yaml
contactPoints:
  - name: "slack-alerts"
    orgId: 1
    receivers:
      - type: "slack"
        settings:
          url: "https://hooks.slack.com/services/XXXX/YYYY/ZZZZ"
          recipient: "#alerts"
          title: "{{ .CommonLabels.alertname }}"
          text: "{{ .CommonAnnotations.summary }}"
          username: "Grafana Alerts"
          icon_emoji: ":warning:"
          mention_channel: "here"
        disableResolveMessage: false
```

### PagerDuty Settings

```yaml
contactPoints:
  - name: "pagerduty-critical"
    orgId: 1
    receivers:
      - type: "pagerduty"
        settings:
          integrationKey: "..."       # Use Vault
          severity: "critical"          # critical, error, warning, info
          class: "infrastructure"
          component: "kubernetes"
          group: "platform"
          summary: "{{ .CommonAnnotations.summary }}"
        disableResolveMessage: false
```

### Opsgenie Settings

```yaml
contactPoints:
  - name: "opsgenie-alerts"
    orgId: 1
    receivers:
      - type: "opsgenie"
        settings:
          apiKey: "..."                # Use Vault
          apiUrl: "https://api.opsgenie.com"
          message: "{{ .CommonLabels.alertname }}"
          description: "{{ .CommonAnnotations.description }}"
          autoClose: true
          overridePriority: true
          sendTagsAs: "both"
        disableResolveMessage: false
```

### Telegram Settings

```yaml
contactPoints:
  - name: "telegram-alerts"
    orgId: 1
    receivers:
      - type: "telegram"
        settings:
          bottoken: "..."              # Use Vault
          chatid: "-1001234567890"
          message: "<b>{{ .CommonLabels.alertname }}</b>"
          parse_mode: "HTML"
          disable_web_page_preview: true
        disableResolveMessage: false
```

### Microsoft Teams Settings

```yaml
contactPoints:
  - name: "teams-alerts"
    orgId: 1
    receivers:
      - type: "teams"
        settings:
          url: "https://..."           # Teams webhook URL (use Vault)
          title: "{{ .CommonLabels.alertname }}"
          message: "{{ .CommonAnnotations.summary }}"
          sectiontitle: "Alert Details"
        disableResolveMessage: false
```

---

## Notification Policies

**Files**:
- Shared: `base/alerting/_default/notification_policies.yaml`
- Environment: `envs/{env}/alerting/{Org Name}/notification_policies.yaml`

Defines routing for alerts to contact points. Uses Grafana's native format — one policy per organization.

```yaml
policies:
  - orgId: 1                         # Required: Numeric org ID
    receiver: "default-contact"      # Required: Default contact point
    group_by:                         # Optional: Grouping labels
      - "alertname"
      - "severity"
    group_wait: "30s"                # Optional: Initial wait
    group_interval: "5m"             # Optional: Interval between groups
    repeat_interval: "4h"            # Optional: Repeat interval
    routes:                           # Optional: Child route policies
      - receiver: "webhook-critical"
        object_matchers:
          - ["severity", "=", "critical"]
        continue: false
```

### Example

```yaml
# envs/prod/alerting/Main Organization/notification_policies.yaml
policies:
  - orgId: 1
    receiver: "email-prod"
    group_by:
      - "alertname"
      - "severity"
    group_wait: "30s"
    group_interval: "5m"
    repeat_interval: "4h"
    routes:
      # Critical alerts → webhook
      - receiver: "webhook-critical"
        object_matchers:
          - ["severity", "=", "critical"]
        group_wait: "10s"
        repeat_interval: "15m"
        continue: false

      # Warning alerts → email
      - receiver: "email-warnings"
        object_matchers:
          - ["severity", "=", "warning"]
        continue: true

      # Team-specific routing
      - receiver: "email-platform"
        object_matchers:
          - ["team", "=", "platform"]
```

---

## Mute Timings

**Files**:
- Shared: `base/alerting/mute_timings.yaml`
- Environment: `envs/{env}/alerting/mute_timings.yaml`

Defines time periods during which alerts should be muted (suppressed).

### All Parameters

```yaml
mute_timings:
  - name: "Mute Timing Name"        # Required: Unique name
    org: "Organization Name"        # Required: Parent organization
    disable_provenance: false       # Optional: Allow UI modification
    intervals:                      # Required: Time intervals
      - times:                      # Optional: Time of day ranges
          - start_time: "HH:MM"
            end_time: "HH:MM"
        weekdays: ["monday:friday"] # Optional: Days of week
        days_of_month: ["1:7"]      # Optional: Days of month (1-31)
        months: ["january:march"]   # Optional: Months
        years: ["2024:2025"]        # Optional: Years
        location: "America/New_York" # Optional: Timezone
```

### Interval Field Reference

| Field | Format | Example |
|-------|--------|---------|
| `times` | `HH:MM` 24-hour format | `start_time: "22:00", end_time: "06:00"` |
| `weekdays` | Day name or range | `["monday", "wednesday:friday"]` |
| `days_of_month` | Number or range | `["1", "15:20", "-1"]` (-1 = last day) |
| `months` | Month name or range | `["january", "march:may"]` |
| `years` | Year or range | `["2024", "2025:2026"]` |
| `location` | IANA timezone | `"America/New_York"`, `"UTC"` |

### Examples

#### Maintenance Window

```yaml
mute_timings:
  - name: "maintenance-window"
    org: "Main Organization"
    intervals:
      - times:
          - start: "02:00"
            end: "04:00"
        weekdays: ["sunday"]
        location: "UTC"
```

#### Weekend Muting

```yaml
mute_timings:
  - name: "weekends"
    org: "Main Organization"
    intervals:
      - weekdays: ["saturday", "sunday"]
```

#### Holiday Period

```yaml
mute_timings:
  - name: "holidays-2024"
    org: "Main Organization"
    intervals:
      - days_of_month: ["24:26"]
        months: ["december"]
        years: ["2024"]
      - days_of_month: ["1"]
        months: ["january"]
        years: ["2025"]
```

### Using Mute Timings

Reference mute timings in notification policies:

```yaml
policies:
  - org: "Main Organization"
    receiver: "email-alerts"
    routes:
      - receiver: "email-warnings"
        object_matchers:
          - ["severity", "=", "warning"]
        mute_timings:
          - "maintenance-window"
          - "weekends"
```

---

## Dashboard JSON

**Location**: `base/dashboards/<Org Name>/<folder-uid>/*.json` and `envs/{env}/dashboards/<Org Name>/<folder-uid>/*.json`

Dashboards are standard Grafana JSON exports. The system supports:

1. **Shared dashboards** - Deployed to ALL environments
2. **Environment-specific dashboards** - Override or add dashboards per environment

### Directory Structure

```
dashboards/
├── shared/                              # Deployed to ALL environments
│   └── Main Organization/
│       ├── infrastructure/
│       │   ├── node-exporter.json
│       │   └── kubernetes-cluster.json
│       └── applications/
│           └── api-gateway.json
├── myenv/                               # Environment-specific dashboards
│   └── Main Organization/
│       └── infrastructure/
│           └── debug-dashboard.json
└── prod/                                # Prod-only dashboards
    ├── Main Organization/
    │   └── business/
    │       └── executive-summary.json
    └── Platform Team/
        └── sre/
            └── sre-overview.json
```

### Override Behavior

Environment-specific dashboards **override** shared dashboards with the same filename:

| Scenario | Result |
|----------|--------|
| Dashboard only in `shared/` | Deployed to all environments |
| Dashboard only in `prod/` | Deployed only to production |
| Dashboard in both `shared/` and `prod/` | Prod uses `prod/` version, others use `shared/` |

### Dashboard Template

Use datasource variables for portability across environments:

```json
{
  "uid": "unique-dashboard-id",
  "title": "Dashboard Title",
  "tags": ["team", "category"],
  "templating": {
    "list": [
      {
        "name": "datasource",
        "type": "datasource",
        "query": "prometheus"
      }
    ]
  },
  "panels": [
    {
      "datasource": {
        "type": "prometheus",
        "uid": "${datasource}"
      }
    }
  ]
}
```

### Exporting Dashboards

```bash
# Export via API
curl -s "http://localhost:3000/api/dashboards/uid/my-dashboard" \
  -H "Authorization: Bearer $TOKEN" | jq '.dashboard' > base/dashboards/folder/my-dashboard.json

# For environment-specific dashboard
curl -s "http://localhost:3000/api/dashboards/uid/debug-dashboard" \
  -H "Authorization: Bearer $TOKEN" | jq '.dashboard' > dashboards/npr/infrastructure/debug-dashboard.json
```

### Use Cases

| Use Case | Location |
|----------|----------|
| Standard monitoring dashboards | `base/dashboards/` |
| Debug/development tools | `dashboards/npr/` |
| Performance testing views | `dashboards/preprod/` |
| Executive summaries | `dashboards/prod/` |
| Environment-specific thresholds | Override in `envs/{env}/dashboards/` |
