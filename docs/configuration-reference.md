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

All resources follow a **shared + environment-specific** pattern where environment configs override shared ones:

| Resource | Shared Location | Env Location | Merge Key |
|----------|----------------|--------------|-----------|
| Datasources | `config/shared/datasources.yaml` | `config/{env}/datasources.yaml` | `uid` |
| Alert Rules | `config/shared/alerting/alert_rules.yaml` | `config/{env}/alerting/alert_rules.yaml` | `name` |
| Contact Points | `config/shared/alerting/contact_points.yaml` | `config/{env}/alerting/contact_points.yaml` | `name` |
| Notification Policies | `config/shared/alerting/notification_policies.yaml` | `config/{env}/alerting/notification_policies.yaml` | `org` |
| Dashboards | `dashboards/shared/{folder}/` | `dashboards/{env}/{folder}/` | filename |

**Shared-only resources** (no environment override):
- Organizations: `config/shared/organizations.yaml`
- Folders: `config/shared/folders.yaml`
- Teams: `config/shared/teams.yaml`
- Service Accounts: `config/shared/service_accounts.yaml`

---

## Organizations

**File**: `config/shared/organizations.yaml`

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

**File**: `config/shared/folders.yaml`

Defines the folder structure for organizing dashboards. Folders can be assigned to specific organizations.

```yaml
folders:
  - title: "Folder Name"          # Required: Display name
    uid: "folder-uid"             # Required: Unique identifier
    org: "Organization Name"      # Optional: Parent organization (defaults to Main)
```

### Example

```yaml
folders:
  # Main Organization folders
  - title: "Infrastructure"
    uid: "infrastructure"
    org: "Main Organization"
    
  - title: "Applications"
    uid: "applications"
    org: "Main Organization"
    
  # Platform Team folders
  - title: "Kubernetes"
    uid: "platform-kubernetes"
    org: "Platform Team"
    
  # Application Team folders
  - title: "API Services"
    uid: "app-api"
    org: "Application Team"
```

---

## Datasources

**Files**: 
- Shared: `config/shared/datasources.yaml`
- Environment: `config/{env}/datasources.yaml`

Defines data sources with full parameter support. Environment-specific datasources override shared ones with the same `uid`.

### All Parameters

```yaml
datasources:
  - name: "Datasource Name"        # Required: Display name
    type: "datasource-type"        # Required: prometheus, loki, postgres, etc.
    uid: "unique-id"               # Required: Unique identifier
    url: "http://host:port"        # Required: Connection URL
    org: "Organization Name"       # Optional: Parent organization
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
- name: "My Prometheus"
  type: "prometheus"
  uid: "prometheus-main"
  url: "http://prometheus:9090"
  org: "Main Organization"
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
- name: "PostgreSQL"
  type: "postgres"
  uid: "postgres"
  url: "postgres.example.com:5432"
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

**File**: `config/shared/teams.yaml`

Defines teams for access control.

```yaml
teams:
  - name: "Team Name"             # Required: Display name
    org: "Organization Name"      # Optional: Parent organization
    email: "team@example.com"     # Optional: Team email
    members:                      # Optional: Team members
      - email: "user@example.com"
        role: "Member"            # Member or Admin
```

### Example

```yaml
teams:
  - name: "Platform Engineering"
    org: "Platform Team"
    email: "platform@example.com"
    members:
      - email: "alice@example.com"
        role: "Admin"
      - email: "bob@example.com"
        role: "Member"

  - name: "SRE"
    org: "Platform Team"
    members:
      - email: "sre@example.com"
        role: "Admin"
```

---

## Service Accounts

**File**: `config/shared/service_accounts.yaml`

Defines service accounts for API access.

```yaml
service_accounts:
  - name: "Account Name"          # Required: Display name
    org: "Organization Name"      # Optional: Parent organization
    role: "Viewer"                # Required: Viewer, Editor, or Admin
    is_disabled: false            # Optional: Disable account
    tokens:                       # Optional: API tokens
      - name: "token-name"
        expires_at: "2025-12-31"  # Optional: Expiration date
```

### Example

```yaml
service_accounts:
  - name: "ci-cd-deployer"
    org: "Main Organization"
    role: "Editor"
    tokens:
      - name: "github-actions"
        expires_at: "2026-12-31"

  - name: "monitoring-readonly"
    role: "Viewer"
    tokens:
      - name: "prometheus-scraper"
```

---

## Alert Rules

**Files**: 
- Shared: `config/shared/alerting/alert_rules.yaml`
- Environment: `config/{env}/alerting/alert_rules.yaml`

Defines alert rules with full parameter support. Environment-specific rules override shared ones with the same `name`.

### All Parameters

```yaml
alert_rules:
  - name: "Alert Name"              # Required: Display name
    folder: "folder-uid"            # Required: Parent folder UID
    org: "Organization Name"        # Required: Parent organization
    rule_group: "Group Name"        # Required: Rule group name
    condition: "C"                  # Required: Condition reference (ref_id)
    for: "5m"                       # Optional: Pending duration before firing
    interval_seconds: 60            # Optional: Evaluation interval (default: 60)
    
    # State handling parameters
    no_data_state: "NoData"         # Optional: NoData, OK, Alerting, KeepLast
    exec_err_state: "Error"         # Optional: Error, OK, Alerting, KeepLast
    is_paused: false                # Optional: Pause alert evaluation
    disable_provenance: false       # Optional: Allow UI modification
    
    # Annotations and labels
    annotations:                    # Optional: Alert annotations
      summary: "Alert summary"
      description: "Detailed description"
      runbook_url: "https://..."
    labels:                         # Optional: Alert labels
      severity: "critical"
      team: "platform"
    
    # Notification override (optional)
    notification_settings:
      contact_point: "critical-alerts"
      group_by: ["alertname", "severity"]
      group_wait: "30s"
      group_interval: "5m"
      repeat_interval: "4h"
      mute_timings: ["maintenance-window"]
    
    # Query data
    data:                           # Required: Query definitions
      - ref_id: "A"
        datasource_uid: "prometheus"
        relative_time_range:        # Optional: Time range override
          from: 600                 # Seconds from now (600 = 10 min ago)
          to: 0
        model:
          expr: "up == 0"
```

### State Handling Options

| Parameter | Values | Description |
|-----------|--------|-------------|
| `no_data_state` | `NoData`, `OK`, `Alerting`, `KeepLast` | State when query returns no data |
| `exec_err_state` | `Error`, `OK`, `Alerting`, `KeepLast` | State when query execution fails |

### Example with All Parameters

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
- Shared: `config/shared/alerting/contact_points.yaml`
- Environment: `config/{env}/alerting/contact_points.yaml`

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
contact_points:
  - name: "Contact Name"          # Required: Display name
    org: "Organization Name"      # Required: Parent organization
    type: "contact-type"          # Required: Contact type from list above
    disable_provenance: false     # Optional: Allow UI modification
    use_vault: true/false         # Optional: Fetch secrets from Vault
    settings:                     # Required: Type-specific settings
      # See type-specific settings below
```

### Email Settings

```yaml
- name: "email-alerts"
  org: "Main Organization"
  type: "email"
  settings:
    addresses: "team@example.com,oncall@example.com"
    single_email: true
    subject: "[{{ .Status }}] {{ .CommonLabels.alertname }}"
    message: |
      {{ range .Alerts }}
      Alert: {{ .Labels.alertname }}
      Status: {{ .Status }}
      {{ end }}
    disable_resolve_message: false
```

### Webhook Settings

```yaml
- name: "webhook-critical"
  org: "Main Organization"
  type: "webhook"
  use_vault: true
  settings:
    url: "https://alerts.example.com/webhook"
    http_method: "POST"
    basic_auth_user: "user"           # Optional
    basic_auth_password: "pass"       # Optional (use Vault)
    authorization_scheme: "Bearer"    # Optional
    authorization_credentials: "..."  # Optional (use Vault)
    max_alerts: 10                    # Optional
    message: "{{ .CommonAnnotations.summary }}"
    title: "{{ .CommonLabels.alertname }}"
    disable_resolve_message: false
```

### Slack Settings

```yaml
- name: "slack-alerts"
  org: "Main Organization"
  type: "slack"
  use_vault: true  # token stored in Vault
  settings:
    recipient: "#alerts"
    token: "xoxb-..."               # Use Vault
    text: "{{ .CommonAnnotations.summary }}"
    title: "{{ .CommonLabels.alertname }}"
    username: "Grafana Alerts"
    icon_emoji: ":warning:"
    mention_channel: "here"         # or "channel"
    mention_users: "U12345,U67890"
    mention_groups: "G12345"
    disable_resolve_message: false
```

### PagerDuty Settings

```yaml
- name: "pagerduty-critical"
  org: "Main Organization"
  type: "pagerduty"
  use_vault: true  # integration_key stored in Vault
  settings:
    integration_key: "..."          # Use Vault
    severity: "critical"            # critical, error, warning, info
    class: "infrastructure"
    component: "kubernetes"
    group: "platform"
    summary: "{{ .CommonAnnotations.summary }}"
    source: "grafana"
    client: "Grafana"
    client_url: "https://grafana.example.com"
    disable_resolve_message: false
```

### Opsgenie Settings

```yaml
- name: "opsgenie-alerts"
  org: "Main Organization"
  type: "opsgenie"
  use_vault: true  # api_key stored in Vault
  settings:
    api_key: "..."                  # Use Vault
    url: "https://api.opsgenie.com" # or api.eu.opsgenie.com
    message: "{{ .CommonLabels.alertname }}"
    description: "{{ .CommonAnnotations.description }}"
    auto_close: true
    override_priority: true
    send_tags_as: "both"            # both, teams, tags
    responders:
      - type: "team"
        name: "Platform Team"
    disable_resolve_message: false
```

### Telegram Settings

```yaml
- name: "telegram-alerts"
  org: "Main Organization"
  type: "telegram"
  use_vault: true  # token stored in Vault
  settings:
    token: "..."                    # Use Vault
    chat_id: "-1001234567890"
    message: "<b>{{ .CommonLabels.alertname }}</b>"
    parse_mode: "HTML"              # HTML or MarkdownV2
    disable_web_page_preview: true
    disable_notifications: false
    disable_resolve_message: false
```

### Microsoft Teams Settings

```yaml
- name: "teams-alerts"
  org: "Main Organization"
  type: "teams"
  use_vault: true  # url stored in Vault
  settings:
    url: "https://..."              # Teams webhook URL (use Vault)
    title: "{{ .CommonLabels.alertname }}"
    message: "{{ .CommonAnnotations.summary }}"
    section_title: "Alert Details"
    disable_resolve_message: false
```

---

## Notification Policies

**File**: `config/{env}/alerting/notification_policies.yaml`

Defines routing for alerts to contact points.

```yaml
notification_policies:
  default_contact_point: "email-default"    # Required: Default receiver
  group_by:                                  # Optional: Grouping labels
    - "alertname"
    - "severity"
  group_wait: "30s"                         # Optional: Initial wait
  group_interval: "5m"                      # Optional: Interval between groups
  repeat_interval: "4h"                     # Optional: Repeat interval
  policies:                                  # Optional: Child policies
    - matchers:
        - label: "severity"
          match: "="
          value: "critical"
      contact_point: "webhook-critical"
      continue: false
```

### Example

```yaml
notification_policies:
  default_contact_point: "email-prod"
  group_by:
    - "alertname"
    - "severity"
  group_wait: "30s"
  group_interval: "5m"
  repeat_interval: "4h"
  
  policies:
    # Critical alerts → webhook
    - matchers:
        - label: "severity"
          match: "="
          value: "critical"
      contact_point: "webhook-critical"
      group_wait: "10s"
      repeat_interval: "15m"
      continue: false
    
    # Warning alerts → email
    - matchers:
        - label: "severity"
          match: "="
          value: "warning"
      contact_point: "email-warnings"
      continue: true
    
    # Team-specific routing
    - matchers:
        - label: "team"
          match: "="
          value: "platform"
      contact_point: "email-platform"
```

---

## Mute Timings

**Files**: 
- Shared: `config/shared/alerting/mute_timings.yaml`
- Environment: `config/{env}/alerting/mute_timings.yaml`

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
          - start_time: "02:00"
            end_time: "04:00"
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
notification_policies:
  - org: "Main Organization"
    contact_point: "email"
    routes:
      - matchers:
          - label: "severity"
            match: "="
            value: "warning"
        contact_point: "email-warnings"
        mute_timings:
          - "maintenance-window"
          - "weekends"
```

---

## Dashboard JSON

**Location**: `dashboards/shared/{folder}/*.json` and `dashboards/{env}/{folder}/*.json`

Dashboards are standard Grafana JSON exports. The system supports:

1. **Shared dashboards** - Deployed to ALL environments
2. **Environment-specific dashboards** - Override or add dashboards per environment

### Directory Structure

```
dashboards/
├── shared/                    # Deployed to ALL environments
│   ├── infrastructure/
│   │   ├── node-exporter.json
│   │   ├── kubernetes-cluster.json
│   │   └── network-overview.json
│   ├── applications/
│   │   ├── api-gateway.json
│   │   └── backend-services.json
│   ├── business/
│   │   └── revenue-metrics.json
│   ├── slos/
│   │   └── slo-overview.json
│   └── alerts/
│       └── alert-overview.json
├── npr/                       # NPR-only dashboards
│   └── infrastructure/
│       └── debug-dashboard.json
├── preprod/                   # PreProd-only dashboards
│   └── (empty or custom dashboards)
└── prod/                      # Prod-only dashboards
    └── business/
        └── executive-summary.json
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
  -H "Authorization: Bearer $TOKEN" | jq '.dashboard' > dashboards/shared/folder/my-dashboard.json

# For environment-specific dashboard
curl -s "http://localhost:3000/api/dashboards/uid/debug-dashboard" \
  -H "Authorization: Bearer $TOKEN" | jq '.dashboard' > dashboards/npr/infrastructure/debug-dashboard.json
```

### Use Cases

| Use Case | Location |
|----------|----------|
| Standard monitoring dashboards | `dashboards/shared/` |
| Debug/development tools | `dashboards/npr/` |
| Performance testing views | `dashboards/preprod/` |
| Executive summaries | `dashboards/prod/` |
| Environment-specific thresholds | Override in `dashboards/{env}/` |
