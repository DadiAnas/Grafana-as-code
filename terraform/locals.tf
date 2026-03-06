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
  # Reads from: {base,env}/folders/<OrgName>/folders.yaml  (per-org dirs)
  # Falls back gracefully if no files exist.
  # =============================================================================
  shared_folder_files = toset(fileset("${local.base_path}/folders", "*/folders.yaml"))
  env_folder_files    = toset(fileset("${local.env_path}/folders", "*/folders.yaml"))

  shared_folders_all = flatten([
    for f in local.shared_folder_files : [
      for folder in try(yamldecode(file("${local.base_path}/folders/${f}")).folders, []) :
      merge(folder, dirname(f) != "_default" && try(folder.org, null) == null ? { org = dirname(f) } : {})
    ]
  ])
  env_folders_all = flatten([
    for f in local.env_folder_files : [
      for folder in try(yamldecode(file("${local.env_path}/folders/${f}")).folders, []) :
      merge(folder, dirname(f) != "_default" && try(folder.org, null) == null ? { org = dirname(f) } : {})
    ]
  ])

  # Create maps by org:uid for merging (env overrides base; org derived from dir name when missing)
  shared_folder_map = { for f in local.shared_folders_all : "${coalesce(try(f.org, null), try(tostring(f.orgId), "_"))}:${f.uid}" => f }
  env_folder_map    = { for f in local.env_folders_all : "${coalesce(try(f.org, null), try(tostring(f.orgId), "_"))}:${f.uid}" => f }
  merged_folder_map = merge(local.shared_folder_map, local.env_folder_map)

  folders_config = {
    folders = values(local.merged_folder_map)
  }

  # =============================================================================
  # Teams (base + environment-specific merged)
  # Reads from: {base,env}/teams/<OrgName>/teams.yaml  (per-org dirs)
  # =============================================================================
  shared_team_files = toset(fileset("${local.base_path}/teams", "*/teams.yaml"))
  env_team_files    = toset(fileset("${local.env_path}/teams", "*/teams.yaml"))

  shared_teams_all = flatten([
    for f in local.shared_team_files : [
      for team in try(yamldecode(file("${local.base_path}/teams/${f}")).teams, []) :
      merge(team, dirname(f) != "_default" && try(team.org, null) == null ? { org = dirname(f) } : {})
    ]
  ])
  env_teams_all = flatten([
    for f in local.env_team_files : [
      for team in try(yamldecode(file("${local.env_path}/teams/${f}")).teams, []) :
      merge(team, dirname(f) != "_default" && try(team.org, null) == null ? { org = dirname(f) } : {})
    ]
  ])

  # Create maps by name/org for merging (env overrides base; org derived from dir name when missing)
  shared_team_map = { for t in local.shared_teams_all : "${t.name}/${coalesce(try(t.org, null), try(tostring(t.orgId), "_"))}" => t }
  env_team_map    = { for t in local.env_teams_all : "${t.name}/${coalesce(try(t.org, null), try(tostring(t.orgId), "_"))}" => t }
  merged_team_map = merge(local.shared_team_map, local.env_team_map)

  teams_config = {
    teams = values(local.merged_team_map)
  }

  # =============================================================================
  # Service Accounts (base + environment-specific merged)
  # Reads from: {base,env}/service_accounts/<OrgName>/service_accounts.yaml
  # =============================================================================
  shared_sa_files = toset(fileset("${local.base_path}/service_accounts", "*/service_accounts.yaml"))
  env_sa_files    = toset(fileset("${local.env_path}/service_accounts", "*/service_accounts.yaml"))

  shared_service_accounts_all = flatten([
    for f in local.shared_sa_files : [
      for sa in try(yamldecode(file("${local.base_path}/service_accounts/${f}")).service_accounts, []) :
      merge(sa, dirname(f) != "_default" && try(sa.org, null) == null ? { org = dirname(f) } : {})
    ]
  ])
  env_service_accounts_all = flatten([
    for f in local.env_sa_files : [
      for sa in try(yamldecode(file("${local.env_path}/service_accounts/${f}")).service_accounts, []) :
      merge(sa, dirname(f) != "_default" && try(sa.org, null) == null ? { org = dirname(f) } : {})
    ]
  ])

  # Create maps by org:name for merging (env overrides base; org derived from dir name when missing)
  shared_sa_map = { for sa in local.shared_service_accounts_all : "${coalesce(try(sa.org, null), try(tostring(sa.orgId), "_"))}:${sa.name}" => sa }
  env_sa_map    = { for sa in local.env_service_accounts_all : "${coalesce(try(sa.org, null), try(tostring(sa.orgId), "_"))}:${sa.name}" => sa }
  merged_sa_map = merge(local.shared_sa_map, local.env_sa_map)

  service_accounts_config = {
    service_accounts = values(local.merged_sa_map)
  }

  # =============================================================================
  # Datasources (base + environment-specific merged)
  # Reads from: {base,env}/datasources/<OrgName>/datasources.yaml  (per-org dirs)
  # =============================================================================
  shared_ds_files = toset(fileset("${local.base_path}/datasources", "*/datasources.yaml"))
  env_ds_files    = toset(fileset("${local.env_path}/datasources", "*/datasources.yaml"))

  shared_datasources_all = flatten([
    for f in local.shared_ds_files : [
      for ds in try(yamldecode(file("${local.base_path}/datasources/${f}")).datasources, []) :
      merge(ds, dirname(f) != "_default" && try(ds.org, null) == null ? { org = dirname(f) } : {})
    ]
  ])
  env_datasources_all = flatten([
    for f in local.env_ds_files : [
      for ds in try(yamldecode(file("${local.env_path}/datasources/${f}")).datasources, []) :
      merge(ds, dirname(f) != "_default" && try(ds.org, null) == null ? { org = dirname(f) } : {})
    ]
  ])

  # Create maps by org:uid for merging (env overrides base; org derived from dir name when missing)
  shared_ds_map = { for ds in local.shared_datasources_all : "${coalesce(try(ds.org, null), try(tostring(ds.orgId), "_"))}:${ds.uid}" => ds }
  env_ds_map    = { for ds in local.env_datasources_all : "${coalesce(try(ds.org, null), try(tostring(ds.orgId), "_"))}:${ds.uid}" => ds }
  merged_ds_map = merge(local.shared_ds_map, local.env_ds_map)

  datasources_config = {
    datasources = values(local.merged_ds_map)
  }

  # =============================================================================
  # Alert Rules (base + environment-specific merged)
  # Reads from: {base,env}/alerting/<OrgName>/alert_rules.yaml  (per-org dirs)
  # =============================================================================
  shared_ar_files = toset(fileset("${local.base_path}/alerting", "*/alert_rules.yaml"))
  env_ar_files    = toset(fileset("${local.env_path}/alerting", "*/alert_rules.yaml"))

  shared_alert_rules_all = flatten([
    for f in local.shared_ar_files : [
      for g in try(yamldecode(file("${local.base_path}/alerting/${f}")).groups, []) :
      merge(g, dirname(f) != "_default" && try(g.org, null) == null ? { org = dirname(f) } : {})
    ]
  ])
  env_alert_rules_all = flatten([
    for f in local.env_ar_files : [
      for g in try(yamldecode(file("${local.env_path}/alerting/${f}")).groups, []) :
      merge(g, dirname(f) != "_default" && try(g.org, null) == null ? { org = dirname(f) } : {})
    ]
  ])

  shared_ar_map = { for g in local.shared_alert_rules_all : "${coalesce(try(g.org, null), try(tostring(g.orgId), "_"))}:${g.folder}-${g.name}" => g }
  env_ar_map    = { for g in local.env_alert_rules_all : "${coalesce(try(g.org, null), try(tostring(g.orgId), "_"))}:${g.folder}-${g.name}" => g }
  merged_ar_map = merge(local.shared_ar_map, local.env_ar_map)

  alert_rules_config = {
    groups = values(local.merged_ar_map)
  }

  # =============================================================================
  # Contact Points (base + environment-specific merged)
  # Reads from: {base,env}/alerting/<OrgName>/contact_points.yaml  (per-org dirs)
  # =============================================================================
  shared_cp_files = toset(fileset("${local.base_path}/alerting", "*/contact_points.yaml"))
  env_cp_files    = toset(fileset("${local.env_path}/alerting", "*/contact_points.yaml"))

  shared_contact_points_all = flatten([
    for f in local.shared_cp_files : [
      for cp in try(yamldecode(file("${local.base_path}/alerting/${f}")).contactPoints, []) :
      merge(cp, dirname(f) != "_default" && try(cp.org, null) == null ? { org = dirname(f) } : {})
    ]
  ])
  env_contact_points_all = flatten([
    for f in local.env_cp_files : [
      for cp in try(yamldecode(file("${local.env_path}/alerting/${f}")).contactPoints, []) :
      merge(cp, dirname(f) != "_default" && try(cp.org, null) == null ? { org = dirname(f) } : {})
    ]
  ])

  shared_cp_map = { for cp in local.shared_contact_points_all : "${coalesce(try(cp.org, null), try(tostring(cp.orgId), "_"))}:${cp.name}" => cp }
  env_cp_map    = { for cp in local.env_contact_points_all : "${coalesce(try(cp.org, null), try(tostring(cp.orgId), "_"))}:${cp.name}" => cp }
  merged_cp_map = merge(local.shared_cp_map, local.env_cp_map)

  contact_points_config = {
    contactPoints = values(local.merged_cp_map)
  }

  # =============================================================================
  # Notification Policies (base + environment-specific merged)
  # Reads from: {base,env}/alerting/<OrgName>/notification_policies.yaml
  # =============================================================================
  shared_np_files = toset(fileset("${local.base_path}/alerting", "*/notification_policies.yaml"))
  env_np_files    = toset(fileset("${local.env_path}/alerting", "*/notification_policies.yaml"))

  shared_notification_policies_all = flatten([
    for f in local.shared_np_files : [
      for np in try(yamldecode(file("${local.base_path}/alerting/${f}")).policies, []) :
      merge(np, dirname(f) != "_default" && try(np.org, null) == null ? { org = dirname(f) } : {})
    ]
  ])
  env_notification_policies_all = flatten([
    for f in local.env_np_files : [
      for np in try(yamldecode(file("${local.env_path}/alerting/${f}")).policies, []) :
      merge(np, dirname(f) != "_default" && try(np.org, null) == null ? { org = dirname(f) } : {})
    ]
  ])

  shared_np_map = { for np in local.shared_notification_policies_all : coalesce(try(np.org, null), try(tostring(np.orgId), "unknown")) => np }
  env_np_map    = { for np in local.env_notification_policies_all : coalesce(try(np.org, null), try(tostring(np.orgId), "unknown")) => np }
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
