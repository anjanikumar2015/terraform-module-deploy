data "azurerm_client_config" "current" {}
data "azurerm_resource_group" "rgs" {
  for_each = {
    for rg in local.rg : rg.name => rg if rg.existing
  }
  name                                          = each.key
}
data "azurerm_proximity_placement_group" "ppg" {
  for_each = {
    for ppg in local.ppg : ppg.name => ppg if ppg.existing
  }
  name                                          = each.key
  resource_group_name                           = each.value.rg
  depends_on = [
    azurerm_proximity_placement_group.ppg
  ]
}
data "azurerm_availability_set" "avsets" {
  for_each = {
    for avset in local.avset : avset.name => avset if avset.existing
  }
  name                                        = each.key
  resource_group_name                         = each.value.rg
  depends_on = [
    azurerm_proximity_placement_group.ppg
  ]
}
data "azurerm_virtual_network" "vnet" {
  name                                        = var.inputs.vnet.name
  resource_group_name                         = var.inputs.vnet.rg
}
data "azurerm_subnet" "subnets" {
  for_each = toset(data.azurerm_virtual_network.vnet.subnets)
  name                                        = each.key
  resource_group_name                         = var.inputs.vnet.rg
  virtual_network_name                        = var.inputs.vnet.name
}
data "azurerm_backup_policy_vm" "rsv" {
  for_each = toset([
    for policy in try(local.backups, {}) : policy.policy if merge({ policy = null }, policy).policy != null
  ])
  name                                        = each.key
  resource_group_name                         = var.inputs.backup.rg
  recovery_vault_name                         = var.inputs.backup.name
}
locals {

}
data "azurerm_storage_account" "storage" {
  for_each = {
    for k, v in try(local.vmdiags, {}): k => v if !v.remote
  }
  name                                        = each.value.sa_name
  resource_group_name                         = each.value.rg
}
data "azurerm_storage_account" "storage_remote" {
  for_each = {
    for k, v in try(local.vmdiags, {}): k => v if v.remote
  }
  provider                                    = azurerm.remote
  name                                        = each.value.sa_name
  resource_group_name                         = each.value.rg
}
data "azurerm_storage_account" "net_diags" {
  for_each = {
    for k, v in try(local.netdiags, {}): k => v if !v.remote
  }
  name                                        = each.value.sa_name
  resource_group_name                         = each.value.rg
}
data "azurerm_storage_account" "net_diags_remote" {
  for_each = {
    for k, v in try(local.netdiags, {}): k => v if v.remote
  }
  provider                                    = azurerm.remote
  name                                        = each.value.sa_name
  resource_group_name                         = each.value.rg
}
data "azurerm_storage_account_sas" "storage" {
  count                                       = local.vmdiags != null ? 1 : 0
  connection_string                           = local.connection_string
  https_only                                  = true
  resource_types {
      service   = false
      container = true
      object    = true
  }
  services {
      blob  = true
      queue = false
      table = true
      file  = false
  }
  start  = timestamp()
  expiry = timeadd(timestamp(), "30m")
  permissions {
      read    = false
      write   = true
      delete  = false
      list    = true
      add     = true
      create  = true
      update  = true
      process = false
  }
}
data "azurerm_log_analytics_workspace" "loganalytics" {
  for_each = {
    for k, v in try(local.log_analytics, {}): k => v if !v.remote
  }
  name                                        = each.value.la_name
  resource_group_name                         = each.value.rg
}
data "azurerm_log_analytics_workspace" "loganalytics_remote" {
  for_each = {
    for k, v in try(local.log_analytics, {}): k => v if v.remote
  }
  provider                                    = azurerm.remote
  name                                        = each.value.la_name
  resource_group_name                         = each.value.rg
}
data "azurerm_netapp_account" "netapp" {
  for_each = {
    for netapp in try(local.netapp, {}) : netapp.account => netapp if !netapp.remote
  }                                           
  name                                        = each.key
  resource_group_name                         = each.value.rg
}
data "azurerm_netapp_account" "netapp_remote" {
  for_each = {
    for netapp in try(local.netapp, {}) : netapp.account => netapp if netapp.remote
  }
  provider                                    = azurerm.remote                                           
  name                                        = each.key
  resource_group_name                         = each.value.rg
}
data "azurerm_netapp_pool" "netapp" {
  for_each = {
    for netapp in try(local.netapp, {}) : netapp.pool => netapp if !netapp.remote
  }
  name                                            = each.key
  account_name                                    = each.value.account
  resource_group_name                             = each.value.rg
}
data "azurerm_netapp_pool" "netapp_remote" {
  for_each = {
    for netapp in try(local.netapp, {}) : netapp.pool => netapp if netapp.remote
  }
  provider                                        = azurerm.remote
  name                                            = each.key
  account_name                                    = each.value.account
  resource_group_name                             = each.value.rg
}
data "azurerm_key_vault" "kv" {
  for_each = {
    for k, v in try(local.secrets, {}): k => v if v.remote != true && v.kv_id == null
  }
  name                                        = each.value.kv_name
  resource_group_name                         = each.value.rg
}
data "azurerm_key_vault" "kv_remote" {
  for_each = {
    for k, v in try(local.secrets, {}): k => v if v.remote == true
  }
  provider                                    = azurerm.remote
  name                                        = each.value.kv_name
  resource_group_name                         = each.value.rg
}
data "azurerm_key_vault_secret" "secret" {
  for_each = {
    for k, v in try(local.secrets, {}): k => v if v.remote != true
  }
  key_vault_id                                = try(data.azurerm_key_vault.kv[0].id, each.value.kv_id)
  name                                        = each.value.secret
}
data "azurerm_key_vault_secret" "secret_remote" {
  for_each = {
    for k, v in try(local.secrets, {}): k => v if v.remote == true
  }
  provider                                    = azurerm.remote
  key_vault_id                                = data.azurerm_key_vault.kv_remote[0].id
  name                                        = each.value.secret
}
data "azurerm_public_ip" "pub_ips" {
  for_each = local.pub_ips
  name                                        = each.key
  resource_group_name                         = each.value.rg
  depends_on = [
    azurerm_public_ip.pub_ips
  ]
}
data "azurerm_monitor_diagnostic_categories" "pub_ips" {
  for_each = {
    for k, v in try(local.pub_ips, {}) : k => v
  }
  resource_id                                   = data.azurerm_public_ip.pub_ips[each.key].id
  depends_on = [
    azurerm_public_ip.pub_ips
  ]
}
data "azurerm_monitor_diagnostic_categories" "lb" {
  for_each = {
    for k, v in try(local.ilb, {}) : k => v
  }
  resource_id                                   = try(azurerm_lb.ilb[each.key].id, azurerm_lb.elb[each.key].id)
  depends_on = [
    azurerm_network_interface_backend_address_pool_association.lb
  ]
}
data "azurerm_monitor_diagnostic_categories" "nics" {
  for_each = {
    for k, v in try(local.nic, {}) : k => v
  }
  resource_id                                   = azurerm_network_interface.nic[each.value.name].id
  depends_on = [
    azurerm_network_interface.nic
  ]
}