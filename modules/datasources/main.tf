# =============================================================================
# DATASOURCES MODULE
# =============================================================================
# This module creates Grafana data sources with full parameter support.
# It handles all datasource types dynamically through json_data configuration.
#
# SUPPORTED PARAMETERS (top-level):
# - name: (required) Data source name
# - type: (required) Data source type (prometheus, loki, postgres, mysql, etc.)
# - uid: Unique identifier
# - url: Data source URL
# - org: Organization name (resolved via org_ids map)
# - orgId: Organization ID (numeric fallback)
# - is_default: Whether this is the default datasource
# - access_mode: proxy or direct
# - basic_auth_enabled: Enable basic auth
# - basic_auth_username: Basic auth username
# - database_name: Database name (for SQL datasources)
# - username: Database/API username
# - http_headers: Custom HTTP headers (map)
# - json_data: Type-specific configuration (object, passed as json_data_encoded)
# - secure_json_data: Sensitive configuration (API keys, passwords)
# - use_vault: Load secrets from Vault
#
# TYPE-SPECIFIC json_data REFERENCE:
#
# PROMETHEUS (type: "prometheus"):
#   httpMethod: "POST" | "GET"          # HTTP method for queries
#   timeInterval: "15s"                 # Scrape interval / min step
#   queryTimeout: "60s"                 # Query timeout
#   prometheusType: "Prometheus" | "Mimir" | "Thanos" | "Cortex"
#   prometheusVersion: "2.40.0"         # Version hint for features
#   customQueryParameters: "key=value"  # Extra query params
#   disableMetricsLookup: false         # Disable metric name completion
#   incrementalQuerying: true           # Incremental query support
#   incrementalQueryOverlapWindow: "10m"# Overlap window for incremental
#   exemplarTraceIdDestinations:        # Link exemplars to traces
#     - name: "traceId"
#       datasourceUid: "tempo-uid"
#   cacheLevel: "Low" | "Medium" | "High" | "None"
#   codeModeEnabled: true               # Enable code mode in query editor
#   manageAlerts: true                  # Use for Grafana-managed alerts
#
# LOKI (type: "loki"):
#   maxLines: 1000                      # Max log lines per query
#   derivedFields:                      # Derived fields (link to traces)
#     - name: "traceId"
#       matcherRegex: "traceID=(\\w+)"
#       url: ""
#       datasourceUid: "tempo-uid"
#       matcherType: "label"
#   alertmanager: ""                    # Alertmanager datasource UID
#   timeout: "60s"                      # Query timeout
#   predefinedOperations: ""            # Default LogQL operations
#
# ALLOY / OPENTELEMETRY:
#   (Uses prometheus type with specific prometheusType or custom json_data)
#   httpMethod: "POST"
#   timeInterval: "15s"
#
# TEMPO (type: "tempo"):
#   tracesToLogsV2:                     # Trace-to-logs linking
#     datasourceUid: "loki-uid"
#     filterBySpanID: true
#     filterByTraceID: true
#     spanStartTimeShift: "-1h"
#     spanEndTimeShift: "1h"
#     tags:
#       - key: "service.name"
#         value: "service"
#     customQuery: false
#   tracesToMetrics:                    # Trace-to-metrics linking
#     datasourceUid: "prometheus-uid"
#     spanStartTimeShift: "-1h"
#     spanEndTimeShift: "1h"
#     tags:
#       - key: "service.name"
#         value: "service"
#     queries:
#       - name: "Request rate"
#         query: "sum(rate(traces_spanmetrics_calls_total{$__tags}[5m]))"
#   serviceMap:                         # Service map / graph
#     datasourceUid: "prometheus-uid"
#   nodeGraph:                          # Node graph visualization
#     enabled: true
#   search:                             # Search configuration
#     hide: false
#     filters: []
#   lokiSearch:                         # Loki search for trace discovery
#     datasourceUid: "loki-uid"
#   traceQuery:                         # Trace query settings
#     timeShiftEnabled: true
#     spanStartTimeShift: "30m"
#     spanEndTimeShift: "30m"
#   spanBar:                            # Span bar display
#     type: "Tag"
#     tag: "http.path"
#
# POSTGRES (type: "grafana-postgresql-datasource" or "postgres"):
#   database: "mydb"                    # Database name (in jsonData)
#   sslmode: "disable" | "require" | "verify-ca" | "verify-full"
#   maxOpenConns: 100                   # Max open connections
#   maxIdleConns: 100                   # Max idle connections
#   maxIdleConnsAuto: true              # Auto-manage idle connections
#   connMaxLifetime: 14400              # Connection max lifetime (seconds)
#   postgresVersion: 1500               # Postgres version * 100 (15.x = 1500)
#   timescaledb: false                  # Enable TimescaleDB features
#   tlsAuth: false                      # Enable TLS client auth
#   tlsAuthWithCACert: false            # Enable TLS with CA cert
#   tlsConfigurationMethod: "file-path" # TLS config method
#   tlsSkipVerify: false                # Skip TLS verification
# =============================================================================

locals {
  # Merge Vault credentials with datasource configuration
  datasources_with_credentials = {
    for ds in var.datasources.datasources : ds.uid => merge(ds, {
      # If use_vault is true, merge Vault secrets into secure_json_data
      secure_json_data = try(ds.use_vault, false) ? merge(
        try(ds.secure_json_data, {}),
        try(var.vault_credentials[ds.name], {})
      ) : try(ds.secure_json_data, {})
    })
  }
}

resource "grafana_data_source" "datasources" {
  for_each = local.datasources_with_credentials

  # ==========================================================================
  # REQUIRED PARAMETERS
  # ==========================================================================
  name = each.value.name
  type = each.value.type

  # ==========================================================================
  # IDENTITY & ORGANIZATION
  # ==========================================================================
  uid    = each.value.uid
  org_id = try(var.org_ids[each.value.org], null) != null ? var.org_ids[each.value.org] : try(tonumber(each.value.orgId), null)

  # ==========================================================================
  # CONNECTION SETTINGS
  # ==========================================================================
  url         = try(each.value.url, null)
  access_mode = try(each.value.access_mode, "proxy")

  # ==========================================================================
  # BASIC AUTHENTICATION
  # ==========================================================================
  basic_auth_enabled  = try(each.value.basic_auth_enabled, false)
  basic_auth_username = try(each.value.basic_auth_username, null)

  # ==========================================================================
  # DATABASE SETTINGS (for SQL datasources)
  # ==========================================================================
  database_name = try(each.value.database_name, null)
  username      = try(each.value.username, null)

  # ==========================================================================
  # DEFAULT DATASOURCE
  # ==========================================================================
  is_default = try(each.value.is_default, false)

  # ==========================================================================
  # CUSTOM HTTP HEADERS
  # ==========================================================================
  http_headers = try(each.value.http_headers, null)

  # ==========================================================================
  # TYPE-SPECIFIC CONFIGURATION (json_data)
  # ==========================================================================
  # All type-specific params are passed through json_data as a YAML object.
  # See the module header comment for the full reference per datasource type.
  # The YAML object is serialized to JSON for the Terraform provider.
  # ==========================================================================
  json_data_encoded = try(jsonencode(each.value.json_data), null)

  # ==========================================================================
  # SECURE/SENSITIVE CONFIGURATION (secure_json_data)
  # ==========================================================================
  # Sensitive settings like passwords, API keys, tokens, and TLS certs.
  # Prefer using Vault (use_vault: true) to inject these at apply time.
  #
  # Common secure_json_data fields:
  #   password            — DB/API password (postgres, mysql, etc.)
  #   basicAuthPassword   — Basic auth password (prometheus, loki, etc.)
  #   tlsCACert           — TLS CA certificate PEM
  #   tlsClientCert       — TLS client certificate PEM
  #   tlsClientKey        — TLS client key PEM
  #   httpHeaderValue1..N — Sensitive HTTP header values (Bearer tokens)
  #   accessKey/secretKey — Cloud provider credentials (CloudWatch)
  #   token               — API token (InfluxDB, etc.)
  # ==========================================================================
  secure_json_data_encoded = try(
    length(each.value.secure_json_data) > 0 ? jsonencode(each.value.secure_json_data) : null,
    null
  )
}
