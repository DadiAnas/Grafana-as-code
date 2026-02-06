resource "grafana_service_account" "service_accounts" {
  for_each = { for sa in var.service_accounts.service_accounts : sa.name => sa }

  name        = each.value.name
  role        = each.value.role
  is_disabled = try(each.value.is_disabled, false)
  org_id      = try(var.org_ids[each.value.org], null)
}

# Flatten tokens for creation
locals {
  tokens = flatten([
    for sa in var.service_accounts.service_accounts : [
      for token in try(sa.tokens, []) : {
        sa_name         = sa.name
        token_name      = token.name
        seconds_to_live = try(token.seconds_to_live, 0)
        org             = try(sa.org, null)
      }
    ]
  ])
}

resource "grafana_service_account_token" "tokens" {
  for_each = { for t in local.tokens : "${t.sa_name}-${t.token_name}" => t }

  name               = each.value.token_name
  service_account_id = grafana_service_account.service_accounts[each.value.sa_name].id
  seconds_to_live    = each.value.seconds_to_live > 0 ? each.value.seconds_to_live : null
}
