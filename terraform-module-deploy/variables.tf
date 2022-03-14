variable "admin_password" {}
variable "inputs" {}
locals {
  inputs                                        = merge(var.inputs, {})
  tags                                          = merge(var.inputs.tags, {})
  admin_user = merge(
    {
      ssh_key_file       = try(local.inputs.ssh_key_file, null)
      admin_user         = try(local.inputs.admin_user, "locadm")
      admin_password     = try(var.admin_password, null)
    }
  )
  backups = {
    for deploy_key, deploy_data in try(var.inputs.deployments, {}) : deploy_key => merge(
      {
        policy = try(deploy_data.policy, null)
      },
      deploy_data,
    )
  }
  extensions = flatten([
    for deploy_key, deploy_data in try(var.inputs.deployments, {}) : [
      for vm_key, vm_data in try(deploy_data.vms, []) : {
        hostname   = lower(vm_key)
        extensions = lookup(deploy_data, "extensions", [])
        id = (
          deploy_data.type == "linux" ?
          azurerm_linux_virtual_machine.linux[vm_key].id :
          azurerm_windows_virtual_machine.windows[vm_key].id
        )
        tags = merge(
          local.tags,
          try(deploy_data.tags, {}),
          try(vm_data.tags, {})
        )
      }
    ]
  ])
  domain = merge(try(var.inputs.domain, null))
  secrets = flatten([
    for kv_key, kv_data in try(local.inputs.secrets, {}): [
      for secret in try(kv_data.secret, []) : {
        rg                                = try(kv_data.rg, null)
        remote                            = try(kv_data.remote, false)
        kv_name                           = kv_key
        kv_id                             = try(kv_data.key_vault_id, null)
        secret                            = secret
      }
    ]
  ])
  vmdiags = flatten([
    for diag_key, diag_data in try(var.inputs.vmdiags, {}): {
        rg = diag_data.rg
        remote = try(diag_data.remote, false)
        sa_name = diag_key
      }
    ])
    netdiags = flatten([
    for diag_key, diag_data in try(var.inputs.netdiags, {}): {
        rg = diag_data.rg
        remote = try(diag_data.remote, false)
        sa_name = diag_key
      }
    ])
  log_analytics = flatten([
    for la_key, la_data in try(var.inputs.log_analytics, {}): {
        rg = la_data.rg
        remote = try(la_data.remote, false)
        la_name = la_key
      }
  ])
  workspaceId                                 = try(data.azurerm_log_analytics_workspace.loganalytics[0].workspace_id, data.azurerm_log_analytics_workspace.loganalytics_remote[0].workspace_id)
  workspaceKey                                = try(data.azurerm_log_analytics_workspace.loganalytics[0].primary_shared_key, data.azurerm_log_analytics_workspace.loganalytics_remote[0].primary_shared_key)
  connection_string                           = try(data.azurerm_storage_account.storage[0].primary_connection_string, data.azurerm_storage_account.storage_remote[0].primary_connection_string)
  storage_account_uri                         = try(data.azurerm_storage_account.storage[0].primary_blob_endpoint, data.azurerm_storage_account.storage_remote[0].primary_blob_endpoint)
  storage_account                             = try(data.azurerm_storage_account.storage[0].name, data.azurerm_storage_account.storage_remote[0].name)
}