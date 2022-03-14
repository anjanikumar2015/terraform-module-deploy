locals {
  pub_ip_diag = {
      for diag_key, diag_data in try(local.inputs.public_ips, {}) : diag_key => merge(
          {
              name               = "${diag_key}-diag"
              target_resource_id = data.azurerm_public_ip.pub_ips[diag_key].id
              logs               = data.azurerm_monitor_diagnostic_categories.pub_ips[diag_key].logs
              metrics            = data.azurerm_monitor_diagnostic_categories.pub_ips[diag_key].metrics
              diagnostics        = try(diag_data.diagnostics, false)
              enabled            = true
              retention_policy = {
                  enabled = try(diag_data.diagnostics.storage, null) != null ? true : false
                  days    = try(diag_data.diagnostics.storage, null) != null ? try(diag_data.diagnostics.retention, 30) : null
              }
                  log_analytics_workspace_id = try(data.azurerm_log_analytics_workspace.loganalytics[0].id, data.azurerm_log_analytics_workspace.loganalytics_remote[0].id, null)
                  storage_account_id         = try(data.azurerm_storage_account.net_diags[0].id, data.azurerm_storage_account.net_diags_remote[0].id, null)
          }
      ) if(try(diag_data.diagnostics, {}) != {})
  }
  lb_diag = {
      for diag_key, diag_data in try(local.inputs.ilbs, {}) : diag_key => merge(
          {
              name               = "${diag_key}-diag"
              target_resource_id = try(azurerm_lb.ilb[diag_key].id, azurerm_lb.elb[diag_key].id)
              logs               = data.azurerm_monitor_diagnostic_categories.lb[diag_key].logs
              metrics            = data.azurerm_monitor_diagnostic_categories.lb[diag_key].metrics
              diagnostics        = try(diag_data.diagnostics, false)
              enabled            = true
              retention_policy = {
                  enabled = try(diag_data.diagnostics.storage, null) != null ? true : false
                  days    = try(diag_data.diagnostics.storage, null) != null ? try(diag_data.diagnostics.retention, 30) : null
              }
                  log_analytics_workspace_id = try(data.azurerm_log_analytics_workspace.loganalytics[0].id, data.azurerm_log_analytics_workspace.loganalytics_remote[0].id, null)
                  storage_account_id         = try(data.azurerm_storage_account.net_diags[0].id, data.azurerm_storage_account.net_diags_remote[0].id, null)
          }
      ) if(try(diag_data.diagnostics, {}) != {})
  }
  nic_diag = {
      for diag_key, diag_data in try(local.nic, {}) : diag_key => merge(
          {
              name               = "${diag_data.name}-diag"
              target_resource_id = azurerm_network_interface.nic[diag_data.name].id
              logs               = data.azurerm_monitor_diagnostic_categories.nics[diag_key].logs
              metrics            = data.azurerm_monitor_diagnostic_categories.nics[diag_key].metrics
              diagnostics        = try(diag_data.diagnostics, false)
              enabled            = true
              retention_policy = {
                  enabled = try(diag_data.diagnostics.storage, null) != null ? true : false
                  days    = try(diag_data.diagnostics.storage, null) != null ? try(diag_data.diagnostics.retention, 30) : null
              }
                  log_analytics_workspace_id = try(data.azurerm_log_analytics_workspace.loganalytics[0].id, data.azurerm_log_analytics_workspace.loganalytics_remote[0].id, null)
                  storage_account_id         = try(data.azurerm_storage_account.net_diags[0].id, data.azurerm_storage_account.net_diags_remote[0].id, null)
          }
      ) if(try(diag_data.diagnostics, {}) != {})
  }
}
resource "azurerm_monitor_diagnostic_setting" "pub_ips" {
  for_each = {
    for pub_ip in local.pub_ip_diag : pub_ip.name => pub_ip if pub_ip.diagnostics
  }
  name                       = each.value.name
  target_resource_id         = each.value.target_resource_id
  log_analytics_workspace_id = each.value.log_analytics_workspace_id
  storage_account_id         = each.value.storage_account_id

  dynamic "log" {
    for_each = each.value.logs
    content {
      category = log.value
      enabled  = each.value.enabled
      retention_policy {
        enabled = each.value.retention_policy.enabled
        days    = each.value.retention_policy.days
      }
    }
  }
  dynamic "metric" {
    for_each = each.value.metrics
    content {
      category = metric.value
      enabled  = each.value.enabled
      retention_policy {
        enabled = each.value.retention_policy.enabled
        days    = each.value.retention_policy.days
      }
    }
  }
}
resource "azurerm_monitor_diagnostic_setting" "lb" {
  for_each = {
    for lb in local.lb_diag : lb.name => lb if lb.diagnostics
  }
  name                       = each.value.name
  target_resource_id         = each.value.target_resource_id
  log_analytics_workspace_id = each.value.log_analytics_workspace_id
  storage_account_id         = each.value.storage_account_id

  dynamic "log" {
    for_each = each.value.logs
    content {
      category = log.value
      enabled  = each.value.enabled
      retention_policy {
        enabled = each.value.retention_policy.enabled
        days    = each.value.retention_policy.days
      }
    }
  }
  dynamic "metric" {
    for_each = each.value.metrics
    content {
      category = metric.value
      enabled  = each.value.enabled
      retention_policy {
        enabled = each.value.retention_policy.enabled
        days    = each.value.retention_policy.days
      }
    }
  }
}
resource "azurerm_monitor_diagnostic_setting" "nic" {
  for_each = {
    for nic in local.nic_diag : nic.name => nic if nic.diagnostics
  }
  name                       = each.value.name
  target_resource_id         = each.value.target_resource_id
  log_analytics_workspace_id = each.value.log_analytics_workspace_id
  storage_account_id         = each.value.storage_account_id

  dynamic "log" {
    for_each = each.value.logs
    content {
      category = log.value
      enabled  = each.value.enabled
      retention_policy {
        enabled = each.value.retention_policy.enabled
        days    = each.value.retention_policy.days
      }
    }
  }
  dynamic "metric" {
    for_each = each.value.metrics
    content {
      category = metric.value
      enabled  = each.value.enabled
      retention_policy {
        enabled = each.value.retention_policy.enabled
        days    = each.value.retention_policy.days
      }
    }
  }
}