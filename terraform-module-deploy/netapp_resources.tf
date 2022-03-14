locals {
  netapp = {
    for entry in flatten([
        for account_key, account_data in try(local.inputs.netapp.accounts, {}) : [
            for pool_key, pool_data in try(local.inputs.netapp.pools, {}) : [
                for volume_key, volume_data in try(local.inputs.netapp.volumes, {}) : [
                    for index in range(volume_data.number) : merge(
                        volume_data,
                        {
                            volume                                      = "${volume_data.sid}-${volume_key}-${format("%02d", index + 1)}"
                            volume_path                                 = "${volume_data.sid}-${volume_data.volume_path}-${format("%02d", index + 1)}"
                            snapshot_directory_visible                  = try(volume_data.snapshot_directory_visible, false)
                            storage_quota_in_gb                         = try(volume_data.storage_quota_in_gb, 100)
                            protocols                                   = try(volume_data.protocols, ["NFSv4.1"])
                            service_level                               = try(volume_data.service_level, "Standard")
                            export_policy_rules = {
                                rule_index                              = try(volume_data.export_policy_rule.rule_index, 1),
                                allowed_clients                         = try(volume_data.export_policy_rule.allowed_clients, ["0.0.0.0/0"])
                                unix_read_write                         = try(volume_data.export_policy_rule.unix_read_write, true)
                                protocols_enabled                       = try(volume_data.export_policy_rule.protocols, ["NFSv4.1"])
                                root_access_enabled                     = try(volume_data.export_policy_rule.root_access_enabled, true)
                            }
                        },
                        pool_data,
                        {
                            pool                                        = pool_key
                        },
                        account_data,
                        {
                            account                                     = account_key
                            account_rg                                  = account_data.rg
                            subnet                                      = account_data.subnet
                            remote                                      = try(account_data.remote, false)
                        },
                        {
                            tags = merge(
                                    local.tags,
                                    try(account_data.tags, {})
                                )
                        }
                    )
                ]
            ] 
        ]
    ]) : "${entry.account}-${entry.pool}-${entry.volume}" => entry
  }
}
resource "azurerm_netapp_volume" "netapp" {
    for_each = local.netapp
    name                                                            = each.value.volume
    location                                                        = var.inputs.location
    resource_group_name                                             = each.value.account_rg
    account_name                                                    = try(data.azurerm_netapp_account.netapp[each.value.account].name, data.azurerm_netapp_account.netapp_remote[each.value.account].name)
    pool_name                                                       = try(data.azurerm_netapp_pool.netapp[each.value.pool].name, data.azurerm_netapp_pool.netapp_remote[each.value.pool].name)
    volume_path                                                     = each.value.volume_path
    service_level                                                   = each.value.service_level
    subnet_id                                                       = data.azurerm_subnet.subnets[each.value.subnet].id
    storage_quota_in_gb                                             = each.value.storage_quota_in_gb
    protocols                                                       = each.value.protocols
    snapshot_directory_visible                                      = each.value.snapshot_directory_visible

  dynamic "export_policy_rule" {
    for_each = try(each.value.export_policy_rules, null) != null ? [1] : []
        content {
            rule_index                                              = each.value.export_policy_rules.rule_index
            allowed_clients                                         = each.value.export_policy_rules.allowed_clients
            unix_read_write                                         = each.value.export_policy_rules.unix_read_write
            protocols_enabled                                       = each.value.export_policy_rules.protocols_enabled
            root_access_enabled                                     = each.value.export_policy_rules.root_access_enabled
        }
    }
    tags                                                            = each.value.tags
}