# Load configurations from YAML/JSON files
# Base configs are in base/ — deployed to ALL environments
# Environment-specific configs are in envs/<env>/ — override or extend base configs

locals {
  # Environment name
  env = var.environment

  # Root project directory (one level up from terraform/)
  project_root = "${path.module}/.."

  # Config paths
  base_path = "${local.project_root}/base"
  env_path  = "${local.project_root}/envs/${local.env}"

  # =============================================================================
  # Organizations (base + environment-specific merged)
  # Environment-specific orgs override base ones with same name
  # =============================================================================
  shared_organizations = try(yamldecode(file("${local.base_path}/organizations.yaml")), { organizations = [] })
  env_organizations    = try(yamldecode(file("${local.env_path}/organizations.yaml")), { organizations = [] })

  # Create maps by name for merging (env overrides base)
  shared_org_map = { for org in local.shared_organizations.organizations : org.name => org }
  env_org_map    = { for org in local.env_organizations.organizations : org.name => org }
  merged_org_map = merge(local.shared_org_map, local.env_org_map)

  organizations_config = {
    organizations = values(local.merged_org_map)
  }

  # =============================================================================
  # Folders (base + environment-specific merged)
  # Environment-specific folders override base ones with same uid
  # =============================================================================
  shared_folders = try(yamldecode(file("${local.base_path}/folders.yaml")), { folders = [] })
  env_folders    = try(yamldecode(file("${local.env_path}/folders.yaml")), { folders = [] })

  # Create maps by org:uid for merging (env overrides base)
  # Using composite key to handle same folder UID across different orgs
  shared_folder_map = { for f in try(local.shared_folders.folders, []) : "${try(f.org, "_")}:${f.uid}" => f }
  env_folder_map    = { for f in try(local.env_folders.folders, []) : "${try(f.org, "_")}:${f.uid}" => f }
  merged_folder_map = merge(local.shared_folder_map, local.env_folder_map)

  folders_config = {
    folders = values(local.merged_folder_map)
  }

  # =============================================================================
  # Teams (base + environment-specific merged)
  # Environment-specific teams override base ones with same name
  # =============================================================================
  shared_teams = try(yamldecode(file("${local.base_path}/teams.yaml")), { teams = [] })
  env_teams    = try(yamldecode(file("${local.env_path}/teams.yaml")), { teams = [] })

  # Create maps by name/org for merging (env overrides base)
  # Composite key "name/org" supports same team name in different orgs
  shared_team_map = { for t in local.shared_teams.teams : "${t.name}/${try(t.org, "Main Org.")}" => t }
  env_team_map    = { for t in local.env_teams.teams : "${t.name}/${try(t.org, "Main Org.")}" => t }
  merged_team_map = merge(local.shared_team_map, local.env_team_map)

  teams_config = {
    teams = values(local.merged_team_map)
  }

  # =============================================================================
  # Service Accounts (base + environment-specific merged)
  # Environment-specific service accounts override base ones with same name
  # =============================================================================
  shared_service_accounts = try(yamldecode(file("${local.base_path}/service_accounts.yaml")), { service_accounts = [] })
  env_service_accounts    = try(yamldecode(file("${local.env_path}/service_accounts.yaml")), { service_accounts = [] })

  # Create maps by org:name for merging (env overrides base)
  # Using composite key to handle same SA name across different orgs
  shared_sa_map = { for sa in local.shared_service_accounts.service_accounts : "${try(sa.org, "_")}:${sa.name}" => sa }
  env_sa_map    = { for sa in local.env_service_accounts.service_accounts : "${try(sa.org, "_")}:${sa.name}" => sa }
  merged_sa_map = merge(local.shared_sa_map, local.env_sa_map)

  service_accounts_config = {
    service_accounts = values(local.merged_sa_map)
  }

  # =============================================================================
  # Datasources (base + environment-specific merged)
  # Environment-specific datasources override base ones with same uid
  # =============================================================================
  shared_datasources = try(yamldecode(file("${local.base_path}/datasources.yaml")), { datasources = [] })
  env_datasources    = try(yamldecode(file("${local.env_path}/datasources.yaml")), { datasources = [] })

  # Create maps by org:uid for merging (env overrides base)
  # Using composite key to handle same datasource UID across different orgs
  shared_ds_map = { for ds in local.shared_datasources.datasources : "${try(ds.org, "_")}:${ds.uid}" => ds }
  env_ds_map    = { for ds in local.env_datasources.datasources : "${try(ds.org, "_")}:${ds.uid}" => ds }
  merged_ds_map = merge(local.shared_ds_map, local.env_ds_map)

  datasources_config = {
    datasources = values(local.merged_ds_map)
  }

  # =============================================================================
  # Alert Rules (base + environment-specific merged)
  # Uses Grafana's native export format with groups
  # Environment-specific groups are merged with base groups
  # =============================================================================
  shared_alert_rules = try(yamldecode(file("${local.base_path}/alerting/alert_rules.yaml")), { groups = [] })
  env_alert_rules    = try(yamldecode(file("${local.env_path}/alerting/alert_rules.yaml")), { groups = [] })

  # Create maps by org:folder-name for merging (env overrides base)
  shared_ar_map = { for g in try(local.shared_alert_rules.groups, []) : "${try(g.org, "_")}:${g.folder}-${g.name}" => g }
  env_ar_map    = { for g in try(local.env_alert_rules.groups, []) : "${try(g.org, "_")}:${g.folder}-${g.name}" => g }
  merged_ar_map = merge(local.shared_ar_map, local.env_ar_map)

  alert_rules_config = {
    groups = values(local.merged_ar_map)
  }

  # =============================================================================
  # Contact Points (base + environment-specific merged)
  # Uses Grafana's native export format: contactPoints array
  # Environment-specific contact points override base ones with same name
  # =============================================================================
  shared_contact_points = try(yamldecode(file("${local.base_path}/alerting/contact_points.yaml")), { contactPoints = [] })
  env_contact_points    = try(yamldecode(file("${local.env_path}/alerting/contact_points.yaml")), { contactPoints = [] })

  # Create maps by org:name for merging (env overrides base)
  # Using composite key to handle same contact point name across different orgs
  shared_cp_map = { for cp in try(local.shared_contact_points.contactPoints, []) : "${try(cp.org, "_")}:${cp.name}" => cp }
  env_cp_map    = { for cp in try(local.env_contact_points.contactPoints, []) : "${try(cp.org, "_")}:${cp.name}" => cp }
  merged_cp_map = merge(local.shared_cp_map, local.env_cp_map)

  contact_points_config = {
    contactPoints = values(local.merged_cp_map)
  }

  # =============================================================================
  # Notification Policies (base + environment-specific merged)
  # Uses Grafana's native export format: policies array
  # Supports both 'org' (name) and 'orgId' (numeric) for organization reference
  # Environment-specific policies override base ones with same org/orgId
  # =============================================================================
  shared_notification_policies = try(yamldecode(file("${local.base_path}/alerting/notification_policies.yaml")), { policies = [] })
  env_notification_policies    = try(yamldecode(file("${local.env_path}/alerting/notification_policies.yaml")), { policies = [] })

  # Create maps by org name or orgId for merging (env overrides base)
  # Use coalesce to prefer org name over orgId for the key
  shared_np_map = {
    for np in try(local.shared_notification_policies.policies, []) :
    coalesce(try(np.org, null), try(tostring(np.orgId), "unknown")) => np
  }
  env_np_map = {
    for np in try(local.env_notification_policies.policies, []) :
    coalesce(try(np.org, null), try(tostring(np.orgId), "unknown")) => np
  }
  merged_np_map = merge(local.shared_np_map, local.env_np_map)

  notification_policies_config = {
    policies = values(local.merged_np_map)
  }

  # =============================================================================
  # SSO Configuration (base + environment-specific merged)
  # Environment-specific SSO config overrides base
  # =============================================================================
  shared_sso = try(yamldecode(file("${local.base_path}/sso.yaml")), { sso = { enabled = false } })
  env_sso    = try(yamldecode(file("${local.env_path}/sso.yaml")), { sso = {} })

  # Merge: environment-specific SSO overrides base
  sso_config = merge(local.shared_sso.sso, local.env_sso.sso)

  # =============================================================================
  # Keycloak Configuration (base + environment-specific merged)
  # OPTIONAL: Set enabled: true to manage Keycloak client via Terraform
  # =============================================================================
  shared_keycloak = try(yamldecode(file("${local.base_path}/keycloak.yaml")), { keycloak = { enabled = false } })
  env_keycloak    = try(yamldecode(file("${local.env_path}/keycloak.yaml")), { keycloak = {} })

  # Merge: environment-specific Keycloak config overrides base
  keycloak_config = merge(local.shared_keycloak.keycloak, local.env_keycloak.keycloak)

  # =============================================================================
  # Vault integration - Extract names for secret fetching
  # =============================================================================
  # Extract datasource names that need Vault credentials
  datasource_names = toset([
    for ds in local.datasources_config.datasources : ds.name
    if try(ds.use_vault, false)
  ])

  # Extract contact point names that need Vault credentials
  # Now using Grafana native format with contactPoints and receivers
  contact_point_names = toset(flatten([
    for cp in try(local.contact_points_config.contactPoints, []) : [
      for receiver in try(cp.receivers, []) : cp.name
      if try(receiver.settings.authorization_credentials, null) != null &&
      can(regex("vault:", try(receiver.settings.authorization_credentials, "")))
    ]
  ]))
}
