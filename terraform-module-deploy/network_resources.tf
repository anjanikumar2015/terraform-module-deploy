locals {
  nic = flatten([
    for deploy_key, deploy_data in try(local.inputs.deployments, {}) : [
      for vm_key, vm_data in deploy_data.vms : [
        for index in range(length(merge({ nics = [{}] }, vm_data).nics)) : {
          hostname                                  = lower(vm_key)
          name                                      = try(vm_data.nics[index].name, "${lower(vm_key)}_nic${format("%02d", index + 1)}")
          ips                                       = try(vm_data.nics[index].ips, [null])
          subnet                                    = try(vm_data.nics[index].subnet, deploy_data.subnet, "")
          diagnostics                               = try(vm_data.nics[index].diagnostics, false)
          enable_accelerated_networking             = try(deploy_data.enable_accelerated_networking, true)
          rg                                        = deploy_data.rg
          public_ip                                 = try(vm_data.nics[index].public_ip, [null])
          ilb = try(
            vm_data.nics[index].ilb,
            deploy_data.ilb,
            []
          )
          asg = try(
            vm_data.nics[index].asg,
            deploy_data.asg,
            null
          )
          tags = merge(
            local.tags,
            try(deploy_data.tags, {}),
            try(vm_data.tags, {})
          )
        }
      ]
    ]
  ])
  pub_ips = {
    for k, v in try(local.inputs.public_ips, {}) : k => merge(
      {
        sku                                       = "Standard"
        allocation_method                         = "Static"
      },
      v,
      {
        tags = merge(
          local.tags,
          try(v.tags, {})
        )
      }
    )
  }
}
resource "azurerm_public_ip" "pub_ips" {
  for_each = local.pub_ips
	name                                            = each.key
	location                                        = var.inputs.location
	resource_group_name                             = each.value.rg
	allocation_method                               = each.value.allocation_method
	sku                                             = each.value.sku
  tags                                            = each.value.tags
  depends_on = [
    azurerm_resource_group.rgs
  ] 
}
resource "azurerm_network_interface" "nic" {
    for_each = {
      for nic in local.nic : nic.name => nic
    }
    name                                            = each.value.name
    resource_group_name                             = each.value.rg
    location                                        = var.inputs.location
    enable_accelerated_networking                   = each.value.enable_accelerated_networking
    tags                                            = each.value.tags

    depends_on = [
      azurerm_resource_group.rgs
    ] 

  dynamic "ip_configuration" {
    for_each = range(length(each.value.ips))
    content {
      name                                        = "ipconfig${format("%02s", ip_configuration.value + 1)}"
      subnet_id                                   = data.azurerm_subnet.subnets[each.value.subnet].id
      private_ip_address_allocation               = each.value.ips[ip_configuration.value] == null ? "Dynamic" : "Static"
      primary                                     = (ip_configuration.value == 0 ? true : false)
      private_ip_address                          = each.value.ips[ip_configuration.value]
      public_ip_address_id                        = try(azurerm_public_ip.pub_ips[each.value.public_ip].id, null)
    }
  }
}