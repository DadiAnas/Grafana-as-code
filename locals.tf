# Load configurations from YAML/JSON files
# Shared configs are in config/shared/ - deployed to ALL environments
# Environment-specific configs are in config/<env>/ - override or extend shared configs

locals {
  # Environment name (npr, preprod, prod)
  env = var.environment

  # =============================================================================
  # Organizations (shared + environment-specific merged)
  # Environment-specific orgs override shared ones with same name
  # =============================================================================
  shared_organizations = try(yamldecode(file("${path.module}/config/shared/organizations.yaml")), { organizations = [] })
  env_organizations    = try(yamldecode(file("${path.module}/config/${local.env}/organizations.yaml")), { organizations = [] })

  # Create maps by name for merging (env overrides shared)
  shared_org_map = { for org in local.shared_organizations.organizations : org.name => org }
  env_org_map    = { for org in local.env_organizations.organizations : org.name => org }
  merged_org_map = merge(local.shared_org_map, local.env_org_map)

  organizations_config = {
    organizations = values(local.merged_org_map)
  }

  # =============================================================================
  # Folders (shared + environment-specific merged)
  # Environment-specific folders override shared ones with same uid
  # =============================================================================
  shared_folders = try(yamldecode(file("${path.module}/config/shared/folders.yaml")), { folders = [] })
  env_folders    = try(yamldecode(file("${path.module}/config/${local.env}/folders.yaml")), { folders = [] })

  # Create maps by uid for merging (env overrides shared)
  shared_folder_map = { for f in local.shared_folders.folders : f.uid => f }
  env_folder_map    = { for f in local.env_folders.folders : f.uid => f }
  merged_folder_map = merge(local.shared_folder_map, local.env_folder_map)

  folders_config = {
    folders = values(local.merged_folder_map)
  }

  # =============================================================================
  # Teams (shared + environment-specific merged)
  # Environment-specific teams override shared ones with same name
  # =============================================================================
  shared_teams = try(yamldecode(file("${path.module}/config/shared/teams.yaml")), { teams = [] })
  env_teams    = try(yamldecode(file("${path.module}/config/${local.env}/teams.yaml")), { teams = [] })

  # Create maps by name for merging (env overrides shared)
  shared_team_map = { for t in local.shared_teams.teams : t.name => t }
  env_team_map    = { for t in local.env_teams.teams : t.name => t }
  merged_team_map = merge(local.shared_team_map, local.env_team_map)

  teams_config = {
    teams = values(local.merged_team_map)
  }

  # =============================================================================
  # Service Accounts (shared + environment-specific merged)
  # Environment-specific service accounts override shared ones with same name
  # =============================================================================
  shared_service_accounts = try(yamldecode(file("${path.module}/config/shared/service_accounts.yaml")), { service_accounts = [] })
  env_service_accounts    = try(yamldecode(file("${path.module}/config/${local.env}/service_accounts.yaml")), { service_accounts = [] })

  # Create maps by name for merging (env overrides shared)
  shared_sa_map = { for sa in local.shared_service_accounts.service_accounts : sa.name => sa }
  env_sa_map    = { for sa in local.env_service_accounts.service_accounts : sa.name => sa }
  merged_sa_map = merge(local.shared_sa_map, local.env_sa_map)

  service_accounts_config = {
    service_accounts = values(local.merged_sa_map)
  }

  # =============================================================================
  # Datasources (shared + environment-specific merged)
  # Environment-specific datasources override shared ones with same uid
  # =============================================================================
  shared_datasources = try(yamldecode(file("${path.module}/config/shared/datasources.yaml")), { datasources = [] })
  env_datasources    = try(yamldecode(file("${path.module}/config/${local.env}/datasources.yaml")), { datasources = [] })

  # Create maps by uid for merging (env overrides shared)
  shared_ds_map = { for ds in local.shared_datasources.datasources : ds.uid => ds }
  env_ds_map    = { for ds in local.env_datasources.datasources : ds.uid => ds }
  merged_ds_map = merge(local.shared_ds_map, local.env_ds_map)

  datasources_config = {
    datasources = values(local.merged_ds_map)
  }

  # =============================================================================
  # Alert Rules (shared + environment-specific merged)
  # Uses Grafana's native export format with groups
  # Environment-specific groups are merged with shared groups
  # =============================================================================
  shared_alert_rules = try(yamldecode(file("${path.module}/config/shared/alerting/alert_rules.yaml")), { groups = [] })
  env_alert_rules    = try(yamldecode(file("${path.module}/config/${local.env}/alerting/alert_rules.yaml")), { groups = [] })

  # Create maps by folder-name for merging (env overrides shared)
  shared_ar_map = { for g in try(local.shared_alert_rules.groups, []) : "${g.folder}-${g.name}" => g }
  env_ar_map    = { for g in try(local.env_alert_rules.groups, []) : "${g.folder}-${g.name}" => g }
  merged_ar_map = merge(local.shared_ar_map, local.env_ar_map)

  alert_rules_config = {
    groups = values(local.merged_ar_map)
  }

  # =============================================================================
  # Contact Points (shared + environment-specific merged)
  # Environment-specific contact points override shared ones with same name
  # =============================================================================
  shared_contact_points = try(yamldecode(file("${path.module}/config/shared/alerting/contact_points.yaml")), { contact_points = [] })
  env_contact_points    = try(yamldecode(file("${path.module}/config/${local.env}/alerting/contact_points.yaml")), { contact_points = [] })

  # Create maps by name for merging (env overrides shared)
  shared_cp_map = { for cp in local.shared_contact_points.contact_points : cp.name => cp }
  env_cp_map    = { for cp in local.env_contact_points.contact_points : cp.name => cp }
  merged_cp_map = merge(local.shared_cp_map, local.env_cp_map)

  contact_points_config = {
    contact_points = values(local.merged_cp_map)
  }

  # =============================================================================
  # Notification Policies (shared + environment-specific merged)
  # Environment-specific policies override shared ones with same org
  # =============================================================================
  shared_notification_policies = try(yamldecode(file("${path.module}/config/shared/alerting/notification_policies.yaml")), { notification_policies = [] })
  env_notification_policies    = try(yamldecode(file("${path.module}/config/${local.env}/alerting/notification_policies.yaml")), { notification_policies = [] })

  # Create maps by org for merging (env overrides shared)
  shared_np_map = { for np in local.shared_notification_policies.notification_policies : np.org => np }
  env_np_map    = { for np in local.env_notification_policies.notification_policies : np.org => np }
  merged_np_map = merge(local.shared_np_map, local.env_np_map)

  notification_policies_config = {
    notification_policies = values(local.merged_np_map)
  }

  # =============================================================================
  # SSO Configuration (shared + environment-specific merged)
  # Environment-specific SSO config overrides shared
  # =============================================================================
  shared_sso = try(yamldecode(file("${path.module}/config/shared/sso.yaml")), { sso = { enabled = false } })
  env_sso    = try(yamldecode(file("${path.module}/config/${local.env}/sso.yaml")), { sso = {} })

  # Merge: environment-specific SSO overrides shared
  sso_config = merge(local.shared_sso.sso, local.env_sso.sso)

  # =============================================================================
  # Keycloak Configuration (shared + environment-specific merged)
  # OPTIONAL: Set enabled: true to manage Keycloak client via Terraform
  # =============================================================================
  shared_keycloak = try(yamldecode(file("${path.module}/config/shared/keycloak.yaml")), { keycloak = { enabled = false } })
  env_keycloak    = try(yamldecode(file("${path.module}/config/${local.env}/keycloak.yaml")), { keycloak = {} })

  # Merge: environment-specific Keycloak config overrides shared
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
  contact_point_names = toset([
    for cp in local.contact_points_config.contact_points : cp.name
    if try(cp.use_vault, false)
  ])
}
