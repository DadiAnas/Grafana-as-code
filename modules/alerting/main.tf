# =============================================================================
# CONTACT POINTS
# Supports: email, webhook, slack, pagerduty, opsgenie, discord, telegram, teams, googlechat, victorops, pushover, sns, sensugo, threema, webex, line, kafka, oncall
# =============================================================================

locals {
  # Merge Vault credentials with contact point settings
  contact_points_with_credentials = {
    for cp in var.contact_points.contact_points : cp.name => merge(cp, {
      settings = try(cp.use_vault, false) ? merge(
        cp.settings,
        try(var.vault_credentials[cp.name], {})
      ) : cp.settings
    })
  }
}

resource "grafana_contact_point" "contact_points" {
  for_each = local.contact_points_with_credentials

  name               = each.value.name
  org_id             = try(var.org_ids[each.value.org], null)
  disable_provenance = try(each.value.disable_provenance, false)

  # ==========================================================================
  # EMAIL
  # ==========================================================================
  dynamic "email" {
    for_each = each.value.type == "email" ? [each.value.settings] : []
    content {
      addresses               = split(",", lookup(email.value, "addresses", ""))
      single_email            = lookup(email.value, "single_email", lookup(email.value, "singleEmail", false))
      message                 = lookup(email.value, "message", null)
      subject                 = lookup(email.value, "subject", null)
      disable_resolve_message = lookup(email.value, "disable_resolve_message", false)
    }
  }

  # ==========================================================================
  # WEBHOOK
  # ==========================================================================
  dynamic "webhook" {
    for_each = each.value.type == "webhook" ? [each.value.settings] : []
    content {
      url                       = lookup(webhook.value, "url", null)
      http_method               = lookup(webhook.value, "http_method", lookup(webhook.value, "httpMethod", "POST"))
      basic_auth_user           = lookup(webhook.value, "basic_auth_user", lookup(webhook.value, "username", null))
      basic_auth_password       = lookup(webhook.value, "basic_auth_password", lookup(webhook.value, "password", null))
      authorization_scheme      = lookup(webhook.value, "authorization_scheme", null)
      authorization_credentials = lookup(webhook.value, "authorization_credentials", null)
      max_alerts                = lookup(webhook.value, "max_alerts", null)
      message                   = lookup(webhook.value, "message", null)
      title                     = lookup(webhook.value, "title", null)
      headers                   = { for h in lookup(each.value, "headers", []) : h.name => h.value } # map(string)
      disable_resolve_message   = lookup(webhook.value, "disable_resolve_message", false)
    }
  }

  # ==========================================================================
  # SLACK
  # ==========================================================================
  dynamic "slack" {
    for_each = each.value.type == "slack" ? [each.value.settings] : []
    content {
      url                     = lookup(slack.value, "url", null)
      token                   = lookup(slack.value, "token", null)
      recipient               = lookup(slack.value, "recipient", null)
      text                    = lookup(slack.value, "text", null)
      title                   = lookup(slack.value, "title", null)
      username                = lookup(slack.value, "username", null)
      icon_emoji              = lookup(slack.value, "icon_emoji", null)
      icon_url                = lookup(slack.value, "icon_url", null)
      mention_channel         = lookup(slack.value, "mention_channel", null)
      mention_users           = lookup(slack.value, "mention_users", null)
      mention_groups          = lookup(slack.value, "mention_groups", null)
      endpoint_url            = lookup(slack.value, "endpoint_url", null)
      disable_resolve_message = lookup(slack.value, "disable_resolve_message", false)
    }
  }

  # ==========================================================================
  # PAGERDUTY
  # ==========================================================================
  dynamic "pagerduty" {
    for_each = each.value.type == "pagerduty" ? [each.value.settings] : []
    content {
      integration_key         = lookup(pagerduty.value, "integration_key", null)
      severity                = lookup(pagerduty.value, "severity", "critical")
      class                   = lookup(pagerduty.value, "class", null)
      component               = lookup(pagerduty.value, "component", null)
      group                   = lookup(pagerduty.value, "group", null)
      summary                 = lookup(pagerduty.value, "summary", null)
      source                  = lookup(pagerduty.value, "source", null)
      client                  = lookup(pagerduty.value, "client", null)
      client_url              = lookup(pagerduty.value, "client_url", null)
      details                 = lookup(pagerduty.value, "details", null)
      url                     = lookup(pagerduty.value, "url", null)
      disable_resolve_message = lookup(pagerduty.value, "disable_resolve_message", false)
    }
  }

  # ==========================================================================
  # OPSGENIE
  # ==========================================================================
  dynamic "opsgenie" {
    for_each = each.value.type == "opsgenie" ? [each.value.settings] : []
    content {
      api_key                 = lookup(opsgenie.value, "api_key", null)
      url                     = lookup(opsgenie.value, "url", lookup(opsgenie.value, "api_url", null))
      message                 = lookup(opsgenie.value, "message", null)
      description             = lookup(opsgenie.value, "description", null)
      auto_close              = lookup(opsgenie.value, "auto_close", null)
      override_priority       = lookup(opsgenie.value, "override_priority", null)
      send_tags_as            = lookup(opsgenie.value, "send_tags_as", null)
      disable_resolve_message = lookup(opsgenie.value, "disable_resolve_message", false)

      dynamic "responders" {
        for_each = try(opsgenie.value.responders, [])
        content {
          type     = lookup(responders.value, "type", null)
          id       = lookup(responders.value, "id", null)
          name     = lookup(responders.value, "name", null)
          username = lookup(responders.value, "username", null)
        }
      }
    }
  }

  # ==========================================================================
  # DISCORD
  # ==========================================================================
  dynamic "discord" {
    for_each = each.value.type == "discord" ? [each.value.settings] : []
    content {
      url                     = lookup(discord.value, "url", null)
      title                   = lookup(discord.value, "title", null)
      message                 = lookup(discord.value, "message", null)
      avatar_url              = lookup(discord.value, "avatar_url", null)
      use_discord_username    = lookup(discord.value, "use_discord_username", null)
      disable_resolve_message = lookup(discord.value, "disable_resolve_message", false)
    }
  }

  # ==========================================================================
  # TELEGRAM
  # ==========================================================================
  dynamic "telegram" {
    for_each = each.value.type == "telegram" ? [each.value.settings] : []
    content {
      token                    = lookup(telegram.value, "token", lookup(telegram.value, "bot_token", null))
      chat_id                  = lookup(telegram.value, "chat_id", null)
      message                  = lookup(telegram.value, "message", null)
      message_thread_id        = lookup(telegram.value, "message_thread_id", null)
      parse_mode               = lookup(telegram.value, "parse_mode", null)
      disable_web_page_preview = lookup(telegram.value, "disable_web_page_preview", null)
      protect_content          = lookup(telegram.value, "protect_content", null)
      disable_notifications    = lookup(telegram.value, "disable_notifications", lookup(telegram.value, "disable_notification", null))
      disable_resolve_message  = lookup(telegram.value, "disable_resolve_message", false)
    }
  }

  # ==========================================================================
  # MICROSOFT TEAMS
  # ==========================================================================
  dynamic "teams" {
    for_each = each.value.type == "teams" ? [each.value.settings] : []
    content {
      url                     = lookup(teams.value, "url", null)
      message                 = lookup(teams.value, "message", null)
      title                   = lookup(teams.value, "title", null)
      section_title           = lookup(teams.value, "section_title", null)
      disable_resolve_message = lookup(teams.value, "disable_resolve_message", false)
    }
  }

  # ==========================================================================
  # GOOGLE CHAT
  # ==========================================================================
  dynamic "googlechat" {
    for_each = each.value.type == "googlechat" ? [each.value.settings] : []
    content {
      url                     = lookup(googlechat.value, "url", null)
      message                 = lookup(googlechat.value, "message", null)
      title                   = lookup(googlechat.value, "title", null)
      disable_resolve_message = lookup(googlechat.value, "disable_resolve_message", false)
    }
  }

  # ==========================================================================
  # VICTOROPS (Splunk On-Call)
  # ==========================================================================
  dynamic "victorops" {
    for_each = each.value.type == "victorops" ? [each.value.settings] : []
    content {
      url                     = lookup(victorops.value, "url", null)
      message_type            = lookup(victorops.value, "message_type", null)
      description             = lookup(victorops.value, "description", null)
      title                   = lookup(victorops.value, "title", null)
      disable_resolve_message = lookup(victorops.value, "disable_resolve_message", false)
    }
  }

  # ==========================================================================
  # PUSHOVER
  # ==========================================================================
  dynamic "pushover" {
    for_each = each.value.type == "pushover" ? [each.value.settings] : []
    content {
      user_key                = lookup(pushover.value, "user_key", null)
      api_token               = lookup(pushover.value, "api_token", null)
      priority                = lookup(pushover.value, "priority", null)
      ok_priority             = lookup(pushover.value, "ok_priority", null)
      retry                   = lookup(pushover.value, "retry", null)
      expire                  = lookup(pushover.value, "expire", null)
      device                  = lookup(pushover.value, "device", null)
      sound                   = lookup(pushover.value, "sound", null)
      ok_sound                = lookup(pushover.value, "ok_sound", null)
      title                   = lookup(pushover.value, "title", null)
      message                 = lookup(pushover.value, "message", null)
      upload_image            = lookup(pushover.value, "upload_image", null)
      disable_resolve_message = lookup(pushover.value, "disable_resolve_message", false)
    }
  }

  # ==========================================================================
  # AWS SNS
  # ==========================================================================
  dynamic "sns" {
    for_each = each.value.type == "sns" ? [each.value.settings] : []
    content {
      topic                   = lookup(sns.value, "topic", null)
      assume_role_arn         = lookup(sns.value, "assume_role_arn", null)
      auth_provider           = lookup(sns.value, "auth_provider", null)
      external_id             = lookup(sns.value, "external_id", null)
      message_format          = lookup(sns.value, "message_format", null)
      subject                 = lookup(sns.value, "subject", null)
      body                    = lookup(sns.value, "body", null)
      disable_resolve_message = lookup(sns.value, "disable_resolve_message", false)
    }
  }

  # ==========================================================================
  # SENSU GO
  # ==========================================================================
  dynamic "sensugo" {
    for_each = each.value.type == "sensugo" ? [each.value.settings] : []
    content {
      url                     = lookup(sensugo.value, "url", null)
      api_key                 = lookup(sensugo.value, "api_key", null)
      entity                  = lookup(sensugo.value, "entity", null)
      check                   = lookup(sensugo.value, "check", null)
      handler                 = lookup(sensugo.value, "handler", null)
      namespace               = lookup(sensugo.value, "namespace", null)
      message                 = lookup(sensugo.value, "message", null)
      disable_resolve_message = lookup(sensugo.value, "disable_resolve_message", false)
    }
  }

  # ==========================================================================
  # THREEMA
  # ==========================================================================
  dynamic "threema" {
    for_each = each.value.type == "threema" ? [each.value.settings] : []
    content {
      gateway_id              = lookup(threema.value, "gateway_id", null)
      recipient_id            = lookup(threema.value, "recipient_id", null)
      api_secret              = lookup(threema.value, "api_secret", null)
      title                   = lookup(threema.value, "title", null)
      description             = lookup(threema.value, "description", null)
      disable_resolve_message = lookup(threema.value, "disable_resolve_message", false)
    }
  }

  # ==========================================================================
  # WEBEX (Cisco Webex)
  # ==========================================================================
  dynamic "webex" {
    for_each = each.value.type == "webex" ? [each.value.settings] : []
    content {
      token                   = lookup(webex.value, "token", null)
      room_id                 = lookup(webex.value, "room_id", null)
      api_url                 = lookup(webex.value, "api_url", null)
      message                 = lookup(webex.value, "message", null)
      disable_resolve_message = lookup(webex.value, "disable_resolve_message", false)
    }
  }

  # ==========================================================================
  # LINE
  # ==========================================================================
  dynamic "line" {
    for_each = each.value.type == "line" ? [each.value.settings] : []
    content {
      token                   = lookup(line.value, "token", null)
      title                   = lookup(line.value, "title", null)
      description             = lookup(line.value, "description", null)
      disable_resolve_message = lookup(line.value, "disable_resolve_message", false)
    }
  }

  # ==========================================================================
  # KAFKA
  # ==========================================================================
  dynamic "kafka" {
    for_each = each.value.type == "kafka" ? [each.value.settings] : []
    content {
      rest_proxy_url          = lookup(kafka.value, "rest_proxy_url", null)
      topic                   = lookup(kafka.value, "topic", null)
      description             = lookup(kafka.value, "description", null)
      details                 = lookup(kafka.value, "details", null)
      username                = lookup(kafka.value, "username", null)
      password                = lookup(kafka.value, "password", null)
      api_version             = lookup(kafka.value, "api_version", null)
      cluster_id              = lookup(kafka.value, "cluster_id", null)
      disable_resolve_message = lookup(kafka.value, "disable_resolve_message", false)
    }
  }

  # ==========================================================================
  # GRAFANA ONCALL
  # ==========================================================================
  dynamic "oncall" {
    for_each = each.value.type == "oncall" ? [each.value.settings] : []
    content {
      url                       = lookup(oncall.value, "url", null)
      http_method               = lookup(oncall.value, "http_method", null)
      basic_auth_user           = lookup(oncall.value, "basic_auth_user", null)
      basic_auth_password       = lookup(oncall.value, "basic_auth_password", null)
      authorization_scheme      = lookup(oncall.value, "authorization_scheme", null)
      authorization_credentials = lookup(oncall.value, "authorization_credentials", null)
      max_alerts                = lookup(oncall.value, "max_alerts", null)
      message                   = lookup(oncall.value, "message", null)
      title                     = lookup(oncall.value, "title", null)
      disable_resolve_message   = lookup(oncall.value, "disable_resolve_message", false)
    }
  }

  # ==========================================================================
  # ALERTMANAGER
  # ==========================================================================
  dynamic "alertmanager" {
    for_each = each.value.type == "alertmanager" ? [each.value.settings] : []
    content {
      url                     = lookup(alertmanager.value, "url", null)
      basic_auth_user         = lookup(alertmanager.value, "basic_auth_user", null)
      basic_auth_password     = lookup(alertmanager.value, "basic_auth_password", null)
      disable_resolve_message = lookup(alertmanager.value, "disable_resolve_message", false)
    }
  }

  # ==========================================================================
  # DINGDING
  # ==========================================================================
  dynamic "dingding" {
    for_each = each.value.type == "dingding" ? [each.value.settings] : []
    content {
      url                     = lookup(dingding.value, "url", null)
      message_type            = lookup(dingding.value, "message_type", null)
      message                 = lookup(dingding.value, "message", null)
      title                   = lookup(dingding.value, "title", null)
      disable_resolve_message = lookup(dingding.value, "disable_resolve_message", false)
    }
  }

  # ==========================================================================
  # WECOM (WeChat Work)
  # ==========================================================================
  dynamic "wecom" {
    for_each = each.value.type == "wecom" ? [each.value.settings] : []
    content {
      url                     = lookup(wecom.value, "url", null)
      secret                  = lookup(wecom.value, "secret", null)
      agent_id                = lookup(wecom.value, "agent_id", null)
      corp_id                 = lookup(wecom.value, "corp_id", null)
      msg_type                = lookup(wecom.value, "msg_type", null)
      message                 = lookup(wecom.value, "message", null)
      title                   = lookup(wecom.value, "title", null)
      to_user                 = lookup(wecom.value, "to_user", null)
      disable_resolve_message = lookup(wecom.value, "disable_resolve_message", false)
    }
  }
}

# =============================================================================
# ALERT RULE GROUPS
# Supports Grafana's native export format with org name instead of orgId
# =============================================================================

locals {
  # Support both new format (groups) and legacy format (alert_rules)
  alert_groups = try(var.alert_rules.groups, [])

  # Convert groups to rule_groups map
  # Key: "folder-groupname", Value: list of rules with org metadata
  rule_groups = {
    for group in local.alert_groups :
    "${group.folder}-${group.name}" => {
      org              = try(group.org, null)
      folder           = group.folder
      name             = group.name
      interval_seconds = try(tonumber(trimsuffix(group.interval, "m")) * 60, try(tonumber(trimsuffix(group.interval, "s")), 60))
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
  org_id             = try(var.org_ids[each.value.org], null)
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
# Full support for all notification policy parameters
# =============================================================================

locals {
  notification_policies_map = {
    for np in var.notification_policies.notification_policies :
    np.org => np
  }
}

resource "grafana_notification_policy" "policy" {
  for_each = local.notification_policies_map

  org_id          = try(var.org_ids[each.key], null)
  contact_point   = each.value.contact_point
  group_by        = try(each.value.group_by, ["alertname"])
  group_wait      = try(each.value.group_wait, "30s")
  group_interval  = try(each.value.group_interval, "5m")
  repeat_interval = try(each.value.repeat_interval, "4h")

  # Nested policies (routes)
  dynamic "policy" {
    for_each = try(each.value.routes, each.value.policies, [])
    content {
      contact_point   = try(policy.value.contact_point, null)
      group_by        = try(policy.value.group_by, [])
      group_wait      = try(policy.value.group_wait, null)
      group_interval  = try(policy.value.group_interval, null)
      repeat_interval = try(policy.value.repeat_interval, null)
      continue        = try(policy.value.continue, false)
      mute_timings    = try(policy.value.mute_timings, [])

      # Matchers for the nested policy
      dynamic "matcher" {
        for_each = try(policy.value.matchers, [])
        content {
          label = matcher.value.label
          match = try(matcher.value.match, "=")
          value = matcher.value.value
        }
      }

      # Legacy match support (key-value pairs)
      dynamic "matcher" {
        for_each = try(policy.value.match, {})
        content {
          label = matcher.key
          match = "="
          value = matcher.value
        }
      }

      # Recursively nested policies (level 2)
      dynamic "policy" {
        for_each = try(policy.value.policies, [])
        content {
          contact_point   = try(policy.value.contact_point, null)
          group_by        = try(policy.value.group_by, [])
          group_wait      = try(policy.value.group_wait, null)
          group_interval  = try(policy.value.group_interval, null)
          repeat_interval = try(policy.value.repeat_interval, null)
          continue        = try(policy.value.continue, false)
          mute_timings    = try(policy.value.mute_timings, [])

          dynamic "matcher" {
            for_each = try(policy.value.matchers, [])
            content {
              label = matcher.value.label
              match = try(matcher.value.match, "=")
              value = matcher.value.value
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
