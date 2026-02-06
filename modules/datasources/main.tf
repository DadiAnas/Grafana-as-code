# =============================================================================
# DATASOURCES MODULE
# =============================================================================
# This module creates Grafana data sources with full parameter support.
# It handles all datasource types dynamically through json_data configuration.
#
# SUPPORTED PARAMETERS:
# - name: (required) Data source name
# - type: (required) Data source type (prometheus, loki, postgres, mysql, etc.)
# - uid: Unique identifier
# - url: Data source URL
# - org: Organization name
# - is_default: Whether this is the default datasource
# - access_mode: proxy or direct
# - basic_auth_enabled: Enable basic auth
# - basic_auth_username: Basic auth username
# - database_name: Database name (for SQL datasources)
# - username: Database/API username
# - password: Database/API password (sensitive - use secure_json_data)
# - http_headers: Custom HTTP headers
# - json_data: Type-specific configuration
# - secure_json_data: Sensitive configuration (API keys, passwords)
# - use_vault: Load secrets from Vault
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
  org_id = try(var.org_ids[each.value.org], null)

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
  # This handles all datasource-type-specific settings dynamically.
  # Common json_data fields by datasource type:
  #
  # PROMETHEUS:
  #   httpMethod, timeInterval, queryTimeout, customQueryParameters
  #   exemplarTraceIdDestinations, incrementalQuerying
  #
  # LOKI:
  #   maxLines, derivedFields, alertmanager
  #
  # POSTGRES/MYSQL:
  #   postgresVersion, sslmode, connMaxLifetime, maxIdleConns, maxOpenConns
  #   timescaledb (for TimescaleDB)
  #
  # ELASTICSEARCH:
  #   esVersion, timeField, logMessageField, logLevelField, maxConcurrentShardRequests
  #
  # INFLUXDB:
  #   version, organization, defaultBucket, httpMode
  #
  # CLOUDWATCH:
  #   authType, assumeRoleArn, externalId, defaultRegion, customMetricsNamespaces
  #
  # TEMPO:
  #   tracesToLogs, tracesToMetrics, nodeGraph, lokiSearch
  #
  # JAEGER/ZIPKIN:
  #   nodeGraph, tracesToLogs
  #
  # GRAPHITE:
  #   graphiteVersion, graphiteType
  #
  # OPENTSDB:
  #   tsdbVersion, tsdbResolution
  # ==========================================================================
  json_data_encoded = try(jsonencode(each.value.json_data), null)

  # ==========================================================================
  # SECURE/SENSITIVE CONFIGURATION (secure_json_data)
  # ==========================================================================
  # This handles all sensitive settings like API keys, passwords, tokens.
  # Common secure_json_data fields:
  #
  # GENERAL:
  #   password, basicAuthPassword, tlsCACert, tlsClientCert, tlsClientKey
  #
  # PROMETHEUS (with auth):
  #   httpHeaderValue1 (for Bearer tokens)
  #
  # CLOUDWATCH:
  #   accessKey, secretKey
  #
  # ELASTICSEARCH:
  #   apiKey
  #
  # INFLUXDB:
  #   token
  #
  # POSTGRES/MYSQL:
  #   password
  # ==========================================================================
  secure_json_data_encoded = try(
    length(each.value.secure_json_data) > 0 ? jsonencode(each.value.secure_json_data) : null,
    null
  )
}
