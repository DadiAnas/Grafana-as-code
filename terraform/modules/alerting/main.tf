# =============================================================================
# CONTACT POINTS
# Uses Grafana's native export format with receivers array
# Supports both 'org' (name) and 'orgId' (numeric) for organization reference
# Supports: email, webhook, slack, pagerduty, opsgenie, discord, telegram, teams, googlechat, victorops, pushover, sns, sensugo, threema, webex, line, kafka, oncall
# =============================================================================

locals {
  # Helper function to resolve org name or ID to numeric ID
  # Priority: orgId (if numeric) > org (name lookup) > default to 1
  resolve_org_id = {
    for cp in try(var.contact_points.contactPoints, []) : "${try(cp.org, "_")}:${cp.name}" => (
      # If orgId is provided and is a number, use it directly
      try(tonumber(cp.orgId), null) != null ? tonumber(cp.orgId) :
      # If org name is provided, look it up in org_ids map
      try(cp.org, null) != null ? try(var.org_ids[cp.org], 1) :
      # Default to org 1 (Main Organization)
      1
    )
  }

  # Create map for contact points - group by org:name to handle same name across orgs
  contact_points_by_name = {
    for cp in try(var.contact_points.contactPoints, []) : "${try(cp.org, "_")}:${cp.name}" => {
      name      = cp.name
      org_id    = local.resolve_org_id["${try(cp.org, "_")}:${cp.name}"]
      receivers = cp.receivers
    }
  }
}


resource "grafana_contact_point" "contact_points" {
  for_each = local.contact_points_by_name

  name               = each.value.name
  org_id             = each.value.org_id
  disable_provenance = false

  # ==========================================================================
  # EMAIL RECEIVERS
  # ==========================================================================
  dynamic "email" {
    for_each = [for r in each.value.receivers : r if r.type == "email"]
    content {
      addresses               = split(";", try(email.value.settings.addresses, ""))
      single_email            = try(email.value.settings.singleEmail, email.value.settings.single_email, false)
      message                 = try(email.value.settings.message, null)
      subject                 = try(email.value.settings.subject, null)
      disable_resolve_message = try(email.value.disableResolveMessage, email.value.disable_resolve_message, false)
    }
  }

  # ==========================================================================
  # WEBHOOK RECEIVERS
  # ==========================================================================
  dynamic "webhook" {
    for_each = [for r in each.value.receivers : r if r.type == "webhook"]
    content {
      url                       = try(webhook.value.settings.url, null)
      http_method               = try(webhook.value.settings.httpMethod, webhook.value.settings.http_method, "POST")
      basic_auth_user           = try(webhook.value.settings.basic_auth_user, webhook.value.settings.username, null)
      basic_auth_password       = try(webhook.value.settings.basic_auth_password, webhook.value.settings.password, null)
      authorization_scheme      = try(webhook.value.settings.authorization_scheme, null)
      authorization_credentials = try(webhook.value.settings.authorization_credentials, null)
      max_alerts                = try(webhook.value.settings.maxAlerts, webhook.value.settings.max_alerts, null)
      message                   = try(webhook.value.settings.message, null)
      title                     = try(webhook.value.settings.title, null)
      headers                   = try(webhook.value.settings.headers, {})
      disable_resolve_message   = try(webhook.value.disableResolveMessage, webhook.value.disable_resolve_message, false)
    }
  }

  # ==========================================================================
  # SLACK RECEIVERS
  # ==========================================================================
  dynamic "slack" {
    for_each = [for r in each.value.receivers : r if r.type == "slack"]
    content {
      url                     = try(slack.value.settings.url, null)
      token                   = try(slack.value.settings.token, null)
      recipient               = try(slack.value.settings.recipient, null)
      text                    = try(slack.value.settings.text, null)
      title                   = try(slack.value.settings.title, null)
      username                = try(slack.value.settings.username, null)
      icon_emoji              = try(slack.value.settings.icon_emoji, null)
      icon_url                = try(slack.value.settings.icon_url, null)
      mention_channel         = try(slack.value.settings.mention_channel, null)
      mention_users           = try(slack.value.settings.mention_users, null)
      mention_groups          = try(slack.value.settings.mention_groups, null)
      endpoint_url            = try(slack.value.settings.endpoint_url, null)
      disable_resolve_message = try(slack.value.disableResolveMessage, false)
    }
  }

  # ==========================================================================
  # PAGERDUTY RECEIVERS
  # ==========================================================================
  dynamic "pagerduty" {
    for_each = [for r in each.value.receivers : r if r.type == "pagerduty"]
    content {
      integration_key         = try(pagerduty.value.settings.integrationKey, pagerduty.value.settings.integration_key, null)
      severity                = try(pagerduty.value.settings.severity, "critical")
      class                   = try(pagerduty.value.settings.class, null)
      component               = try(pagerduty.value.settings.component, null)
      group                   = try(pagerduty.value.settings.group, null)
      summary                 = try(pagerduty.value.settings.summary, null)
      source                  = try(pagerduty.value.settings.source, null)
      client                  = try(pagerduty.value.settings.client, null)
      client_url              = try(pagerduty.value.settings.client_url, null)
      details                 = try(pagerduty.value.settings.details, null)
      url                     = try(pagerduty.value.settings.url, null)
      disable_resolve_message = try(pagerduty.value.disableResolveMessage, false)
    }
  }

  # ==========================================================================
  # OPSGENIE RECEIVERS
  # ==========================================================================
  dynamic "opsgenie" {
    for_each = [for r in each.value.receivers : r if r.type == "opsgenie"]
    content {
      api_key                 = try(opsgenie.value.settings.apiKey, opsgenie.value.settings.api_key, null)
      url                     = try(opsgenie.value.settings.apiUrl, opsgenie.value.settings.url, null)
      message                 = try(opsgenie.value.settings.message, null)
      description             = try(opsgenie.value.settings.description, null)
      auto_close              = try(opsgenie.value.settings.autoClose, opsgenie.value.settings.auto_close, null)
      override_priority       = try(opsgenie.value.settings.overridePriority, opsgenie.value.settings.override_priority, null)
      send_tags_as            = try(opsgenie.value.settings.sendTagsAs, opsgenie.value.settings.send_tags_as, null)
      disable_resolve_message = try(opsgenie.value.disableResolveMessage, false)
    }
  }

  # ==========================================================================
  # DISCORD RECEIVERS
  # ==========================================================================
  dynamic "discord" {
    for_each = [for r in each.value.receivers : r if r.type == "discord"]
    content {
      url                     = try(discord.value.settings.url, null)
      title                   = try(discord.value.settings.title, null)
      message                 = try(discord.value.settings.message, null)
      avatar_url              = try(discord.value.settings.avatar_url, null)
      use_discord_username    = try(discord.value.settings.use_discord_username, null)
      disable_resolve_message = try(discord.value.disableResolveMessage, false)
    }
  }

  # ==========================================================================
  # TELEGRAM RECEIVERS
  # ==========================================================================
  dynamic "telegram" {
    for_each = [for r in each.value.receivers : r if r.type == "telegram"]
    content {
      token                    = try(telegram.value.settings.bottoken, telegram.value.settings.token, null)
      chat_id                  = try(telegram.value.settings.chatid, telegram.value.settings.chat_id, null)
      message                  = try(telegram.value.settings.message, null)
      message_thread_id        = try(telegram.value.settings.message_thread_id, null)
      parse_mode               = try(telegram.value.settings.parse_mode, null)
      disable_web_page_preview = try(telegram.value.settings.disable_web_page_preview, null)
      protect_content          = try(telegram.value.settings.protect_content, null)
      disable_notifications    = try(telegram.value.settings.disable_notifications, null)
      disable_resolve_message  = try(telegram.value.disableResolveMessage, false)
    }
  }

  # ==========================================================================
  # MICROSOFT TEAMS RECEIVERS
  # ==========================================================================
  dynamic "teams" {
    for_each = [for r in each.value.receivers : r if r.type == "teams"]
    content {
      url                     = try(teams.value.settings.url, null)
      message                 = try(teams.value.settings.message, null)
      title                   = try(teams.value.settings.title, null)
      section_title           = try(teams.value.settings.section_title, null)
      disable_resolve_message = try(teams.value.disableResolveMessage, false)
    }
  }

  # ==========================================================================
  # GOOGLE CHAT RECEIVERS
  # ==========================================================================
  dynamic "googlechat" {
    for_each = [for r in each.value.receivers : r if r.type == "googlechat"]
    content {
      url                     = try(googlechat.value.settings.url, null)
      message                 = try(googlechat.value.settings.message, null)
      title                   = try(googlechat.value.settings.title, null)
      disable_resolve_message = try(googlechat.value.disableResolveMessage, false)
    }
  }

  # ==========================================================================
  # VICTOROPS (Splunk On-Call) RECEIVERS
  # ==========================================================================
  dynamic "victorops" {
    for_each = [for r in each.value.receivers : r if r.type == "victorops"]
    content {
      uid                     = try(victorops.value.uid, null)
      url                     = try(victorops.value.settings.url, null)
      message_type            = try(victorops.value.settings.message_type, null)
      description             = try(victorops.value.settings.description, null)
      title                   = try(victorops.value.settings.title, null)
      disable_resolve_message = try(victorops.value.disableResolveMessage, false)
    }
  }

  # ==========================================================================
  # PUSHOVER RECEIVERS
  # ==========================================================================
  dynamic "pushover" {
    for_each = [for r in each.value.receivers : r if r.type == "pushover"]
    content {
      uid                     = try(pushover.value.uid, null)
      user_key                = try(pushover.value.settings.userKey, pushover.value.settings.user_key, null)
      api_token               = try(pushover.value.settings.apiToken, pushover.value.settings.api_token, null)
      priority                = try(pushover.value.settings.priority, null)
      ok_priority             = try(pushover.value.settings.okPriority, pushover.value.settings.ok_priority, null)
      retry                   = try(pushover.value.settings.retry, null)
      expire                  = try(pushover.value.settings.expire, null)
      device                  = try(pushover.value.settings.device, null)
      sound                   = try(pushover.value.settings.sound, null)
      ok_sound                = try(pushover.value.settings.okSound, pushover.value.settings.ok_sound, null)
      title                   = try(pushover.value.settings.title, null)
      message                 = try(pushover.value.settings.message, null)
      upload_image            = try(pushover.value.settings.upload_image, null)
      disable_resolve_message = try(pushover.value.disableResolveMessage, false)
    }
  }

  # ==========================================================================
  # AWS SNS RECEIVERS
  # ==========================================================================
  dynamic "sns" {
    for_each = [for r in each.value.receivers : r if r.type == "sns"]
    content {
      uid                     = try(sns.value.uid, null)
      topic                   = try(sns.value.settings.topic, null)
      assume_role_arn         = try(sns.value.settings.assumeRoleArn, sns.value.settings.assume_role_arn, null)
      auth_provider           = try(sns.value.settings.authProvider, sns.value.settings.auth_provider, null)
      external_id             = try(sns.value.settings.externalId, sns.value.settings.external_id, null)
      message_format          = try(sns.value.settings.messageFormat, sns.value.settings.message_format, null)
      subject                 = try(sns.value.settings.subject, null)
      body                    = try(sns.value.settings.body, null)
      disable_resolve_message = try(sns.value.disableResolveMessage, false)
    }
  }

  # ==========================================================================
  # SENSU GO RECEIVERS
  # ==========================================================================
  dynamic "sensugo" {
    for_each = [for r in each.value.receivers : r if r.type == "sensugo"]
    content {
      uid                     = try(sensugo.value.uid, null)
      url                     = try(sensugo.value.settings.url, null)
      api_key                 = try(sensugo.value.settings.apiKey, sensugo.value.settings.api_key, null)
      entity                  = try(sensugo.value.settings.entity, null)
      check                   = try(sensugo.value.settings.check, null)
      handler                 = try(sensugo.value.settings.handler, null)
      namespace               = try(sensugo.value.settings.namespace, null)
      message                 = try(sensugo.value.settings.message, null)
      disable_resolve_message = try(sensugo.value.disableResolveMessage, false)
    }
  }

  # ==========================================================================
  # THREEMA RECEIVERS
  # ==========================================================================
  dynamic "threema" {
    for_each = [for r in each.value.receivers : r if r.type == "threema"]
    content {
      uid                     = try(threema.value.uid, null)
      gateway_id              = try(threema.value.settings.gatewayId, threema.value.settings.gateway_id, null)
      recipient_id            = try(threema.value.settings.recipientId, threema.value.settings.recipient_id, null)
      api_secret              = try(threema.value.settings.apiSecret, threema.value.settings.api_secret, null)
      title                   = try(threema.value.settings.title, null)
      description             = try(threema.value.settings.description, null)
      disable_resolve_message = try(threema.value.disableResolveMessage, false)
    }
  }

  # ==========================================================================
  # WEBEX (Cisco Webex) RECEIVERS
  # ==========================================================================
  dynamic "webex" {
    for_each = [for r in each.value.receivers : r if r.type == "webex"]
    content {
      uid                     = try(webex.value.uid, null)
      token                   = try(webex.value.settings.token, null)
      room_id                 = try(webex.value.settings.roomId, webex.value.settings.room_id, null)
      api_url                 = try(webex.value.settings.apiUrl, webex.value.settings.api_url, null)
      message                 = try(webex.value.settings.message, null)
      disable_resolve_message = try(webex.value.disableResolveMessage, false)
    }
  }

  # ==========================================================================
  # LINE RECEIVERS
  # ==========================================================================
  dynamic "line" {
    for_each = [for r in each.value.receivers : r if r.type == "line"]
    content {
      uid                     = try(line.value.uid, null)
      token                   = try(line.value.settings.token, null)
      title                   = try(line.value.settings.title, null)
      description             = try(line.value.settings.description, null)
      disable_resolve_message = try(line.value.disableResolveMessage, false)
    }
  }

  # ==========================================================================
  # KAFKA RECEIVERS
  # ==========================================================================
  dynamic "kafka" {
    for_each = [for r in each.value.receivers : r if r.type == "kafka"]
    content {
      uid                     = try(kafka.value.uid, null)
      rest_proxy_url          = try(kafka.value.settings.restProxyUrl, kafka.value.settings.rest_proxy_url, null)
      topic                   = try(kafka.value.settings.topic, null)
      description             = try(kafka.value.settings.description, null)
      details                 = try(kafka.value.settings.details, null)
      username                = try(kafka.value.settings.username, null)
      password                = try(kafka.value.settings.password, null)
      api_version             = try(kafka.value.settings.apiVersion, kafka.value.settings.api_version, null)
      cluster_id              = try(kafka.value.settings.clusterId, kafka.value.settings.cluster_id, null)
      disable_resolve_message = try(kafka.value.disableResolveMessage, false)
    }
  }

  # ==========================================================================
  # GRAFANA ONCALL RECEIVERS
  # ==========================================================================
  dynamic "oncall" {
    for_each = [for r in each.value.receivers : r if r.type == "oncall"]
    content {
      uid                       = try(oncall.value.uid, null)
      url                       = try(oncall.value.settings.url, null)
      http_method               = try(oncall.value.settings.httpMethod, oncall.value.settings.http_method, null)
      basic_auth_user           = try(oncall.value.settings.basicAuthUser, oncall.value.settings.basic_auth_user, null)
      basic_auth_password       = try(oncall.value.settings.basicAuthPassword, oncall.value.settings.basic_auth_password, null)
      authorization_scheme      = try(oncall.value.settings.authorizationScheme, oncall.value.settings.authorization_scheme, null)
      authorization_credentials = try(oncall.value.settings.authorizationCredentials, oncall.value.settings.authorization_credentials, null)
      max_alerts                = try(oncall.value.settings.maxAlerts, oncall.value.settings.max_alerts, null)
      message                   = try(oncall.value.settings.message, null)
      title                     = try(oncall.value.settings.title, null)
      disable_resolve_message   = try(oncall.value.disableResolveMessage, false)
    }
  }

  # ==========================================================================
  # ALERTMANAGER RECEIVERS
  # ==========================================================================
  dynamic "alertmanager" {
    for_each = [for r in each.value.receivers : r if r.type == "alertmanager"]
    content {
      uid                     = try(alertmanager.value.uid, null)
      url                     = try(alertmanager.value.settings.url, null)
      basic_auth_user         = try(alertmanager.value.settings.basicAuthUser, alertmanager.value.settings.basic_auth_user, null)
      basic_auth_password     = try(alertmanager.value.settings.basicAuthPassword, alertmanager.value.settings.basic_auth_password, null)
      disable_resolve_message = try(alertmanager.value.disableResolveMessage, false)
    }
  }

  # ==========================================================================
  # DINGDING RECEIVERS
  # ==========================================================================
  dynamic "dingding" {
    for_each = [for r in each.value.receivers : r if r.type == "dingding"]
    content {
      uid                     = try(dingding.value.uid, null)
      url                     = try(dingding.value.settings.url, null)
      message_type            = try(dingding.value.settings.messageType, dingding.value.settings.message_type, null)
      message                 = try(dingding.value.settings.message, null)
      title                   = try(dingding.value.settings.title, null)
      disable_resolve_message = try(dingding.value.disableResolveMessage, false)
    }
  }

  # ==========================================================================
  # WECOM (WeChat Work) RECEIVERS
  # ==========================================================================
  dynamic "wecom" {
    for_each = [for r in each.value.receivers : r if r.type == "wecom"]
    content {
      uid                     = try(wecom.value.uid, null)
      url                     = try(wecom.value.settings.url, null)
      secret                  = try(wecom.value.settings.secret, null)
      agent_id                = try(wecom.value.settings.agentId, wecom.value.settings.agent_id, null)
      corp_id                 = try(wecom.value.settings.corpId, wecom.value.settings.corp_id, null)
      msg_type                = try(wecom.value.settings.msgType, wecom.value.settings.msg_type, null)
      message                 = try(wecom.value.settings.message, null)
      title                   = try(wecom.value.settings.title, null)
      to_user                 = try(wecom.value.settings.toUser, wecom.value.settings.to_user, null)
      disable_resolve_message = try(wecom.value.disableResolveMessage, false)
    }
  }
}

# =============================================================================
# ALERT RULE GROUPS
# Supports Grafana's native export format
# Supports both 'org' (name) and 'orgId' (numeric) for organization reference
# =============================================================================

locals {
  # Support both new format (groups) and legacy format (alert_rules)
  alert_groups = try(var.alert_rules.groups, [])

  # Convert groups to rule_groups map
  # Key: "org:folder-groupname", Value: list of rules with org metadata
  rule_groups = {
    for group in local.alert_groups :
    "${try(group.org, "_")}:${group.folder}-${group.name}" => {
      org              = try(group.org, null)
      orgId            = try(group.orgId, null)
      folder           = group.folder
      name             = group.name
      interval_seconds = try(tonumber(trimsuffix(group.interval, "m")) * 60, try(tonumber(trimsuffix(group.interval, "s")), 60))
      # Resolve org ID: priority is orgId (if numeric) > org (name lookup) > null
      resolved_org_id = (
        try(tonumber(group.orgId), null) != null ? tonumber(group.orgId) :
        try(group.org, null) != null ? try(var.org_ids[group.org], null) :
        null
      )
      rules = [
        for rule in try(group.rules, []) : {
          name                  = try(rule.title, rule.name)
          uid                   = try(rule.uid, null)
          condition             = rule.condition
          for                   = try(rule.for, "5m")
          annotations           = try(rule.annotations, {})
          labels                = try(rule.labels, {})
          no_data_state         = try(rule.noDataState, try(rule.no_data_state, "NoData"))
          exec_err_state        = try(rule.execErrState, try(rule.exec_err_state, "Error"))
          is_paused             = try(rule.isPaused, try(rule.is_paused, false))
          notification_settings = try(rule.notification_settings, try(rule.notificationSettings, null))
          data = [
            for d in rule.data : {
              ref_id              = try(d.refId, d.ref_id)
              datasource_uid      = try(d.datasourceUid, d.datasource_uid)
              query_type          = try(d.queryType, try(d.query_type, null))
              model               = d.model
              relative_time_range = try(d.relativeTimeRange, try(d.relative_time_range, { from = 600, to = 0 }))
            }
          ]
        }
      ]
    }
  }
}

resource "grafana_rule_group" "rule_groups" {
  for_each = local.rule_groups

  name               = each.value.name
  folder_uid         = each.value.folder
  interval_seconds   = each.value.interval_seconds
  org_id             = each.value.resolved_org_id
  disable_provenance = false

  dynamic "rule" {
    for_each = each.value.rules
    content {
      name        = rule.value.name
      for         = rule.value.for
      condition   = rule.value.condition
      annotations = rule.value.annotations
      labels      = rule.value.labels

      # Alert state configurations
      no_data_state  = rule.value.no_data_state
      exec_err_state = rule.value.exec_err_state
      is_paused      = rule.value.is_paused

      # Notification settings
      dynamic "notification_settings" {
        for_each = rule.value.notification_settings != null ? [rule.value.notification_settings] : []
        content {
          contact_point   = notification_settings.value.contact_point
          group_by        = try(notification_settings.value.group_by, null)
          group_wait      = try(notification_settings.value.group_wait, null)
          group_interval  = try(notification_settings.value.group_interval, null)
          repeat_interval = try(notification_settings.value.repeat_interval, null)
          mute_timings    = try(notification_settings.value.mute_timings, null)
        }
      }

      # Query/Expression data
      dynamic "data" {
        for_each = rule.value.data
        content {
          ref_id         = data.value.ref_id
          datasource_uid = data.value.datasource_uid
          query_type     = data.value.query_type
          model          = jsonencode(data.value.model)

          relative_time_range {
            from = data.value.relative_time_range.from
            to   = data.value.relative_time_range.to
          }
        }
      }
    }
  }
}


# =============================================================================
# NOTIFICATION POLICIES
# Uses Grafana's native export format with orgId and object_matchers
# Supports both 'org' (name) and 'orgId' (numeric) for organization reference
# =============================================================================

locals {
  # Helper function to resolve org name or ID to numeric ID for notification policies
  resolve_np_org_id = {
    for np in try(var.notification_policies.policies, []) : (
      # Use orgId if provided, otherwise use org name, fallback to index
      try(tostring(np.orgId), try(np.org, "unknown"))
      ) => (
      # If orgId is provided and is a number, use it directly
      try(tonumber(np.orgId), null) != null ? tonumber(np.orgId) :
      # If org name is provided, look it up in org_ids map
      try(np.org, null) != null ? try(var.org_ids[np.org], 1) :
      # Default to org 1 (Main Organization)
      1
    )
  }

  # Create map for notification policies
  # Keys must be known at plan time, so we use the Org Name (or static Org ID from config)
  # We do NOT resolve to the dynamic Grafana Org ID for the map key
  notification_policies_map = {
    for np in try(var.notification_policies.policies, []) : (
      # Use org name if provided (static string from YAML)
      try(np.org, null) != null ? np.org :
      # If orgId is provided, use it (static string/number from YAML)
      try(tostring(np.orgId), "default")
      ) => merge(np, {
        # meaningful_id is used for the key
        meaningful_id = try(np.org, try(tostring(np.orgId), "default"))

        # resolved_org_id is used for the resource attribute (can be dynamic)
        resolved_org_id = (
          try(tonumber(np.orgId), null) != null ? tonumber(np.orgId) :
          try(np.org, null) != null ? try(var.org_ids[np.org], 1) :
          1
        )
    })
  }
}

resource "grafana_notification_policy" "policy" {
  for_each = local.notification_policies_map

  org_id          = each.value.resolved_org_id
  contact_point   = each.value.receiver
  group_by        = try(each.value.group_by, ["alertname"])
  group_wait      = try(each.value.group_wait, "30s")
  group_interval  = try(each.value.group_interval, "5m")
  repeat_interval = try(each.value.repeat_interval, "4h")

  # Nested policies (routes)
  dynamic "policy" {
    for_each = try(each.value.routes, [])
    content {
      contact_point   = try(policy.value.receiver, null)
      group_by        = try(policy.value.group_by, [])
      group_wait      = try(policy.value.group_wait, null)
      group_interval  = try(policy.value.group_interval, null)
      repeat_interval = try(policy.value.repeat_interval, null)
      continue        = try(policy.value.continue, false)
      mute_timings    = try(policy.value.mute_timings, [])

      # Grafana native object_matchers format: [[label, operator, value], ...]
      dynamic "matcher" {
        for_each = try(policy.value.object_matchers, [])
        content {
          label = matcher.value[0]
          match = matcher.value[1]
          value = matcher.value[2]
        }
      }

      # Recursively nested policies (level 2)
      dynamic "policy" {
        for_each = try(policy.value.routes, [])
        content {
          contact_point   = try(policy.value.receiver, null)
          group_by        = try(policy.value.group_by, [])
          group_wait      = try(policy.value.group_wait, null)
          group_interval  = try(policy.value.group_interval, null)
          repeat_interval = try(policy.value.repeat_interval, null)
          continue        = try(policy.value.continue, false)
          mute_timings    = try(policy.value.mute_timings, [])

          # Grafana native object_matchers format
          dynamic "matcher" {
            for_each = try(policy.value.object_matchers, [])
            content {
              label = matcher.value[0]
              match = matcher.value[1]
              value = matcher.value[2]
            }
          }
        }
      }
    }
  }

  depends_on = [grafana_contact_point.contact_points]
}

# =============================================================================
# MUTE TIMINGS (Optional)
# =============================================================================

locals {
  mute_timings_map = {
    for mt in try(var.mute_timings.mute_timings, []) :
    "${mt.org}-${mt.name}" => mt
  }
}

resource "grafana_mute_timing" "mute_timings" {
  for_each = local.mute_timings_map

  name   = each.value.name
  org_id = try(var.org_ids[each.value.org], null)

  dynamic "intervals" {
    for_each = each.value.intervals
    content {
      weekdays      = try(intervals.value.weekdays, null)
      days_of_month = try(intervals.value.days_of_month, null)
      months        = try(intervals.value.months, null)
      years         = try(intervals.value.years, null)
      location      = try(intervals.value.location, null)

      dynamic "times" {
        for_each = try(intervals.value.times, [])
        content {
          start = times.value.start
          end   = times.value.end
        }
      }
    }
  }
}
