locals {
    linux = flatten([
        for deploy_key, deploy_data in try(local.inputs.deployments, {}) : [
            for vm_key, vm_data in lookup(deploy_data, "vms", []) : merge(
                {
                    hostname                        = lower(vm_key)
                    backup_policy                   = try(deploy_data.policy, null)
                    asr_policy                      = null
                    avset                           = try(vm_data.avset, null)
                    ppg                             = try(vm_data.ppg, null)
                    avset_id                        = try(vm_data.avset_id, null)
                    ppg_id                          = try(vm_data.ppg_id, null)
                    disks                           = []
                    nics                            = lookup(vm_data, "nics", [{}])
                    boot_diags                      = try(deploy_data.boot_diags, null)
                    os_disk_storage_account_type    = "Premium_LRS"
                    resource_group_name             = deploy_data.rg
                    os_disk_size                    = try(deploy_data.os_disk_size, null)
                    license_type                    = null
                    zone                            = try(vm_data.zone, null)
                },
                deploy_data,
                {
                    tags = merge(
                        local.tags,
                        try(deploy_data.tags, {}),
                        try(vm_data.tags, {})
                    )
                    admin_user = local.admin_user
                }
            )
        ]
    ])
    }
    resource "azurerm_linux_virtual_machine" "linux" {
    for_each = {
        for vm in local.linux : vm.hostname => vm if vm.type == "linux"
    }
    name                                                                            = lower(each.value.hostname)
    size                                                                            = each.value.sku
    zone                                                                            = each.value.zone
    tags                                                                            = each.value.tags
    resource_group_name                                                             = each.value.resource_group_name
    location                                                                        = var.inputs.location
    admin_username                                                                  = var.inputs.admin_user
    admin_password                                                                  = each.value.admin_user.admin_password
    disable_password_authentication                                                 = each.value.admin_user.ssh_key_file != null ? true : false
    custom_data                                                                     = lookup(each.value.admin_user, "custom_data", null) != null ? filebase64(each.value.admin_user.custom_data) : null
    dynamic "admin_ssh_key" {
        for_each = each.value.admin_user.ssh_key_file != null ? [1] : []
        content {
        username   = each.value.admin_user.admin_user
        public_key = file(each.value.admin_user.ssh_key_file)
        }
    }
    network_interface_ids = flatten(
        [
        for nic in local.nic : [
            azurerm_network_interface.nic[nic.name].id
        ] if nic.hostname == each.value.hostname
        ]
    )
    os_disk {
        name                                                                        = "${lower(each.value.hostname)}_os"
        caching                                                                     = "ReadWrite"
        storage_account_type                                                        = each.value.os_disk_storage_account_type
        disk_size_gb                                                                = each.value.os_disk_size
    }
    source_image_id                                                                 = lookup(each.value.os, "resource_id", null)
    license_type                                                                    = each.value.license_type
    dynamic "source_image_reference" {
        for_each = lookup(each.value.os, "marketplace_reference", null) != null ? [1] : []
        content {
        publisher = each.value.os.marketplace_reference.publisher
        offer     = each.value.os.marketplace_reference.offer
        sku       = each.value.os.marketplace_reference.sku
        version   = each.value.os.marketplace_reference.version
        }
    }
    dynamic "plan" {
        for_each = lookup(each.value.os, "plan", null) != null ? [1] : []
        content {
        name      = each.value.os.plan.name
        product   = each.value.os.plan.product
        publisher = each.value.os.plan.publisher
        }
    }
    availability_set_id = (
        lookup(each.value, "avset_id", null) != null ? each.value.avset_id : (
        lookup(each.value, "avset", null) != null ? azurerm_availability_set.avsets[each.value.avset].id : null
        )
    )
    proximity_placement_group_id = (
        lookup(each.value, "ppg_id", null) != null ? each.value.ppg_id : (
        lookup(each.value, "ppg", null) != null ? azurerm_proximity_placement_group.ppg[each.value.ppg].id : null
        )
    )
    dynamic "boot_diagnostics" {
        for_each = each.value.boot_diags ? [1] : []
        content {
        storage_account_uri = local.storage_account_uri
        }
    }
    lifecycle {
        ignore_changes = [
            identity
        ]
    }
    depends_on = [
        azurerm_network_interface.nic
    ]
}
resource "azurerm_backup_protected_vm" "linux" {
    for_each = {
        for vm in local.linux : vm.hostname => vm if vm.backup_policy != null && vm.type == "linux"
    }

    resource_group_name = var.inputs.backup.rg
    recovery_vault_name = var.inputs.backup.name
    source_vm_id        = azurerm_linux_virtual_machine.linux[each.key].id
    backup_policy_id    = data.azurerm_backup_policy_vm.rsv[each.value.backup_policy].id
}
resource "azurerm_virtual_machine_extension" "OmsAgentForLinux" {
    for_each = {
        for vm in local.extensions : vm.hostname => vm if contains(vm.extensions, "OmsAgentForLinux")
    }
    name                            = "OmsAgentForLinux"
    tags                            = each.value.tags
    virtual_machine_id              = each.value.id
    publisher                       = "Microsoft.EnterpriseCloud.Monitoring"
    type                            = "OmsAgentForLinux"
    type_handler_version            = "1.0"
    auto_upgrade_minor_version      = true

    settings = <<SETTINGS
    {
        "workspaceId" : "${local.workspaceId}"
    }
    SETTINGS
    protected_settings = <<PROTECTED_SETTINGS
    {
        "workspaceKey" : "${local.workspaceKey}"
    }
    PROTECTED_SETTINGS
}
resource "azurerm_virtual_machine_extension" "NetworkWatcherAgentLinux" {
    for_each = {
        for vm in local.extensions : vm.hostname => vm if contains(vm.extensions, "NetworkWatcherAgentLinux")
    }
    name                            = "NetworkWatcherAgentLinux"
    tags                            = each.value.tags
    virtual_machine_id              = each.value.id
    publisher                       = "Microsoft.Azure.NetworkWatcher"
    type                            = "NetworkWatcherAgentLinux"
    type_handler_version            = "1.4"
    auto_upgrade_minor_version      = true
    depends_on = [
        azurerm_virtual_machine_extension.LinuxDiagnostic
    ]
}
resource "azurerm_virtual_machine_extension" "DependencyAgentLinux" {
    for_each = {
        for vm in local.extensions : vm.hostname => vm if contains(vm.extensions, "DependencyAgentLinux")
    }
    name                            = "DependencyAgentLinux"
    tags                            = each.value.tags
    virtual_machine_id              = each.value.id
    publisher                       = "Microsoft.Azure.Monitoring.DependencyAgent"
    type                            = "DependencyAgentLinux"
    type_handler_version            = "9.5"
    auto_upgrade_minor_version      = true
    automatic_upgrade_enabled  = true
    depends_on = [
        azurerm_virtual_machine_extension.NetworkWatcherAgentLinux
    ]
}
resource "azurerm_virtual_machine_extension" "MonitorX64Linux" {
    for_each = {
        for vm in local.extensions : vm.hostname => vm if contains(vm.extensions, "MonitorX64Linux")
    }
    name                            = "MonitorX64Linux"
    tags                            = each.value.tags
    virtual_machine_id              = each.value.id
    publisher                       = "Microsoft.AzureCAT.AzureEnhancedMonitoring"
    type                            = "MonitorX64Linux"
    type_handler_version            = "1.0"
    auto_upgrade_minor_version      = true
    settings = <<SETTINGS
    {
        "system": "SAP"
    }
    SETTINGS
    protected_settings = <<PROTECTED_SETTINGS
    {
        "workspaceKey" : "${local.workspaceKey}"
    }
    PROTECTED_SETTINGS
    depends_on = [
        azurerm_virtual_machine_extension.OmsAgentForLinux
    ]
}
resource "azurerm_virtual_machine_extension" "LinuxDiagnostic" {
    for_each = {
        for vm in local.extensions : vm.hostname => vm if contains(vm.extensions, "LinuxDiagnostic")
    }
    name                            = "LinuxDiagnostic"
    tags                            = each.value.tags
    virtual_machine_id              = each.value.id
    publisher                       = "Microsoft.Azure.Diagnostics"
    type                            = "LinuxDiagnostic"
    type_handler_version            = "3.0"
    auto_upgrade_minor_version      = true
    settings                        = templatefile("${path.module}/inputs/linux_diags.json",
        {
        storage_account = local.storage_account,
        resource_id     = each.value.id
    })
    protected_settings = <<PROTECTED_SETTINGS
        {
        "storageAccountName" : "${local.storage_account}",
        "storageAccountSasToken": "${trimprefix(data.azurerm_storage_account_sas.storage[0].sas, "?")}"
        }
    PROTECTED_SETTINGS

    lifecycle {
        ignore_changes = [
            protected_settings
        ]
    }
    depends_on = [
        azurerm_virtual_machine_extension.MonitorX64Linux
    ]
}
resource "azurerm_virtual_machine_extension" "LinuxCustomScript" {
    for_each = {
        for vm in local.extensions : vm.hostname => vm if contains(vm.extensions, "CustomScript")
    }
    name                            = each.value.hostname
    tags                            = each.value.tags
    virtual_machine_id              = each.value.id
    publisher                       = "Microsoft.Azure.Extensions"
    type                            = "CustomScript"
    type_handler_version            = "2.0"
    auto_upgrade_minor_version      = true
    settings = <<SETTINGS
        {
            "commandToExecute": "alternatives --set python /usr/bin/python3"
        }
    SETTINGS
}
resource "azurerm_virtual_machine_extension" "AzureMonitorLinuxAgent" {
    for_each = {
        for vm in local.extensions : vm.hostname => vm if contains(vm.extensions, "AzureMonitorLinuxAgent")
    }
    name                            = "AzureMonitorLinuxAgent"
    tags                            = each.value.tags
    virtual_machine_id              = each.value.id
    publisher                       = "Microsoft.Azure.Monitor"
    type                            = "AzureMonitorLinuxAgent"
    type_handler_version            = "1.5"
    auto_upgrade_minor_version      = true
}