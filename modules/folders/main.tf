resource "grafana_folder" "folders" {
  for_each = { for folder in var.folders.folders : folder.uid => folder }

  title  = each.value.name
  uid    = each.value.uid
  org_id = try(var.org_ids[each.value.org], null)
}
