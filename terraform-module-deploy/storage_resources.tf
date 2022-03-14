locals {
  disks = {
    for deploy_key, deploy_data in try(local.inputs.deployments, {}) : deploy_key => flatten([
      for disk in deploy_data.disks :  [
        for index in range(disk.number) : merge(
          {
            storage_account_type        = "Premium_LRS"
            caching                     = try(deploy_data.disks.caching, "None")
            write_accelerator_enabled   = try(deploy_data.disks.write_accelerator_enabled, false)
            resource_group_name         = deploy_data.rg
          },
          disk,
          {
            name                        = "${disk.name}${format("%02d", index + 1)}"
          }
        )
      ]
    ])
  }
  disk_lun = {
    for deploy_key, deploy_data in local.disks : deploy_key => [
      for index in range(length(deploy_data)) : merge(
        {
          lun                         = index
        },
        deploy_data[index]
      )
    ]
  }
  disk = flatten([
    for deploy_key, deploy_data in try(local.inputs.deployments, {}) : [
      for vm_key, vm_data in deploy_data.vms : [
        for disk in lookup(local.disk_lun, deploy_key) : merge(
          disk,
            {
              hostname                    = vm_key
              type                        = deploy_data.type
              zone                        = merge({ zone = null }, vm_data).zone
              name                        = "${lower(vm_key)}-${disk.name}"
              tags = merge(
                local.tags,
                try(deploy_data.tags, {}),
                try(vm_data.tags, {})
              )
            }
          )
        ]
      ]
    ]
  )
  storage = {
    for storage_key, storage_data in try(local.inputs.storage, {}) : storage_key => merge(
      storage_data,
      {
        existing                                = try(storage_data.existing, false)
        remote                                  = try(storage_data.remote, false)
        account_tier                            = try(storage_data.tier, "Premium")
        account_kind                            = try(storage_data.kind, "FileStorage")
        account_replication_type                = try(storage_data.replication_type, "ZRS")
        min_tls_version                         = try(storage_data.tls_version, "TLS1_2")
        enable_https_traffic_only               = true
        is_hns_enabled                          = false
      },
    )
  }
}
resource "azurerm_managed_disk" "disk" {
    for_each = {
        for disk in local.disk : disk.name => disk
    }

    name                                                = each.value.name
    create_option                                       = "Empty"
    disk_size_gb                                        = each.value.size
    location                                            = var.inputs.location
    resource_group_name                                 = each.value.resource_group_name
    storage_account_type                                = each.value.storage_account_type
    zones                                               = each.value.zone != null ? [each.value.zone] : null
    tags                                                = each.value.tags
    depends_on = [
      azurerm_resource_group.rgs
    ] 
}
resource "azurerm_virtual_machine_data_disk_attachment" "disk" {
    for_each = {
        for disk in local.disk : disk.name => disk
    }

    virtual_machine_id                                  = each.value.type == "linux" ? azurerm_linux_virtual_machine.linux[lower(each.value.hostname)].id : azurerm_windows_virtual_machine.windows[lower(each.value.hostname)].id
    managed_disk_id                                     = azurerm_managed_disk.disk[each.value.name].id
    lun                                                 = each.value.lun
    caching                                             = each.value.caching
    write_accelerator_enabled                           = each.value.write_accelerator_enabled
}
resource "azurerm_storage_account" "storage" {
    for_each = {
        for k, v in local.storage : k => v if !v.existing
    }
    name                                          = each.key
    location                                      = var.inputs.location
    resource_group_name                           = each.value.rg
    account_tier                                  = each.value.account_tier
    account_kind                                  = each.value.account_kind
    account_replication_type                      = each.value.account_replication_type
    enable_https_traffic_only                     = each.value.enable_https_traffic_only
    is_hns_enabled                                = each.value.is_hns_enabled
    min_tls_version                               = each.value.min_tls_version
    depends_on = [
        azurerm_resource_group.rgs
    ]
    tags                                          = local.tags
}