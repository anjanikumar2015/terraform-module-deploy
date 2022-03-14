locals {
  rg = {
    for rg_key, rg_data in try(local.inputs.rgs, {}) : rg_key => merge(
      {
        name                                  = lower(rg_key)
        existing                              = false
      },
      rg_data,
      {
        tags = merge(
          local.tags,
          try(rg_data.tags, {})
        )
      }
    )
  }
  ppg = {
    for ppg_key, ppg_data in try(local.inputs.ppgs, {}) : ppg_key => merge(
      {
        name                                    = lower(ppg_key)
        existing                                = false
      },
      ppg_data,
      {
        tags = merge(
          local.tags,
          try(ppg_data.tags, {})
        )
      }
    )
  }
  avset = {
    for avset_key, avset_data in try(local.inputs.avsets, {}) : avset_key => merge(
      {
          name                                    = lower(avset_key)
          existing                                = false
          avset_id                                = try(avset_data.avset_id, null)
          ppg_id                                  = try(avset_data.ppg_id, azurerm_proximity_placement_group.ppg[avset_data.ppg].id, null)
      },
      avset_data,
      {
          tags = merge(
            local.tags,
            try(avset_data.tags, {})
          )
      }
    )
  }
  ilb = {
    for ilb_key, ilb_data in try(local.inputs.ilbs, {}) : ilb_key => {
      name                                      = lower(ilb_key)
      rg                                        = ilb_data.rg
      type                                      = try(ilb_data.type, "internal")
      public_ip                                 = try(ilb_data.public_ip, null)                         
      backends = flatten([
        for ilbbe_key, ilbbe_data in ilb_data.backends : merge(
          {
            lb                                  = lower(ilb_key)
            app                                 = lower(ilbbe_key)
            ip_address                          = null
            probe_protocol                      = "Tcp"
            interval_in_seconds                 = 5
            number_of_probes                    = 2
            rule_protocol                       = "All"
            idle_timeout_in_minutes             = 30
            enable_floating_ip                  = true
            frontend_port                       = 0
            backend_port                        = 0
            load_distribution                   = "Default"
            availability_zone                   = "Zone-Redundant"
            out_rule_protocol                   = "All"
            out_ports                           = 0
            tcp_reset                           = true
            rg                                  = ilb_data.rg
          },
          ilbbe_data,
        )
      ])
      tags = merge(
        local.tags,
        try(ilb_data.tags, {})
      )
    }
  }
  ilb_be = {
    for be in(
      flatten([
          for k, v in local.ilb : [
            for be_k, be_v in v.backends : be_v
          ]
      ])
    ) : "${be.lb}-${be.app}" => be
  }
  bap_associations = flatten([
    for be in local.ilb_be : [
      for nicdata in local.nic : {
        ref                                   = "${be.lb}-${be.app}-${nicdata.name}"
        nic_id                                = azurerm_network_interface.nic[nicdata.name].id
        ip_configuration_name                 = azurerm_network_interface.nic[nicdata.name].ip_configuration[0].name
        lb_ref                                = be.lb
        be_ref                                = "${be.lb}-${be.app}"
      } if contains(nicdata.ilb, be.app)
    ]
  ])
}
#################################################################################################
##            Terraform to deploy Resource Groups if needed                                    ##
##                                                                                             ##
##                                                                                             ##
#################################################################################################
resource "azurerm_resource_group" "rgs" {
  for_each = {
    for rg in local.rg : rg.name => rg if !rg.existing
  }
  name                                          = each.key
  location                                      = var.inputs.location
  tags                                          = each.value.tags
}
#################################################################################################
##            Terraform to deploy Proximity Placement Groups if needed                         ##
##                                                                                             ##
##                                                                                             ##
#################################################################################################
resource "azurerm_proximity_placement_group" "ppg" {
  for_each = {
    for ppg in local.ppg : ppg.name => ppg if !ppg.existing
  }
  name                                          = each.value.name
  resource_group_name                           = each.value.rg
  location                                      = var.inputs.location
  tags                                          = each.value.tags
  depends_on = [
    azurerm_resource_group.rgs
  ] 
}
#################################################################################################
##            Terraform to deploy Availibility Sets if needed                                  ##
##                                                                                             ##
##                                                                                             ##
#################################################################################################
resource "azurerm_availability_set" "avsets" {
  for_each = {
    for avset in local.avset : avset.name => avset if !avset.existing
  }
  name                                        = each.key
  resource_group_name                         = each.value.rg
  location                                    = var.inputs.location
  platform_update_domain_count                = 20
  platform_fault_domain_count                 = 3
  proximity_placement_group_id                = each.value.ppg_id
  tags                                        = each.value.tags
  managed                                     = true
  depends_on = [
    azurerm_resource_group.rgs
  ]
}
#################################################################################################
##            Terraform to deploy Internal Load Balancers if needed                            ##
##                                                                                             ##
##                                                                                             ##
#################################################################################################
resource "azurerm_lb" "ilb" {
  for_each = {
    for ilb in local.ilb : ilb.name => ilb if ilb.type == "internal"
  }
  name                                      = each.value.name
  resource_group_name                       = each.value.rg
  location                                  = var.inputs.location
  sku                                       = "Standard"

  dynamic "frontend_ip_configuration" {
    iterator                                = fe
    for_each = each.value.backends 
    content {
      name                                  = "${fe.value.app}-frontend"
      subnet_id                             = try(data.azurerm_subnet.subnets[fe.value.subnet].id, null)
      private_ip_address_allocation         = fe.value.ip_address == null ? "Dynamic" : "Static"
      private_ip_address                    = fe.value.ip_address
      availability_zone                     = fe.value.availability_zone
    }
  }
  tags                                      = each.value.tags
  depends_on = [
    azurerm_resource_group.rgs
  ] 
}
resource "azurerm_lb" "elb" {
  for_each = {
    for ilb in local.ilb : ilb.name => ilb if ilb.type == "external"
  }
  name                                      = each.value.name
  resource_group_name                       = each.value.rg
  location                                  = var.inputs.location
  sku                                       = "Standard"

  dynamic "frontend_ip_configuration" {
    iterator                                = fe
    for_each = each.value.backends 
    content {
      name                                  = "${fe.value.app}-frontend"
      public_ip_address_id                  = try(data.azurerm_public_ip.pub_ips[each.value.public_ip].id, null)
    }
  }
  tags                                      = each.value.tags
  depends_on = [
    azurerm_resource_group.rgs
  ] 
}
resource "azurerm_lb_backend_address_pool" "lb" {
  for_each = local.ilb_be
  loadbalancer_id                           = try(azurerm_lb.ilb[each.value.lb].id, azurerm_lb.elb[each.value.lb].id)
  name                                      = "${each.value.app}-backend"
}
resource "azurerm_lb_probe" "lb" {
  for_each = local.ilb_be
  resource_group_name                       = each.value.rg
  loadbalancer_id                           = try(azurerm_lb.ilb[each.value.lb].id, azurerm_lb.elb[each.value.lb].id)
  name                                      = "${each.value.app}-probe"
  port                                      = each.value.probe_port
  protocol                                  = each.value.probe_protocol
  interval_in_seconds                       = each.value.interval_in_seconds
  number_of_probes                          = each.value.number_of_probes
  depends_on = [
    azurerm_lb.ilb
  ] 
}
resource "azurerm_lb_rule" "lb" {
  for_each = local.ilb_be
  resource_group_name                       = each.value.rg
  loadbalancer_id                           = try(azurerm_lb.ilb[each.value.lb].id, azurerm_lb.elb[each.value.lb].id)
  probe_id                                  = azurerm_lb_probe.lb["${each.value.lb}-${each.value.app}"].id
  name                                      = "${each.value.app}-rule"
  protocol                                  = each.value.rule_protocol
  frontend_port                             = each.value.frontend_port
  backend_port                              = each.value.backend_port
  frontend_ip_configuration_name            = "${each.value.app}-frontend"
  backend_address_pool_ids                  = [azurerm_lb_backend_address_pool.lb["${each.value.lb}-${each.value.app}"].id]
  idle_timeout_in_minutes                   = each.value.idle_timeout_in_minutes
  enable_floating_ip                        = each.value.enable_floating_ip
  load_distribution                         = each.value.load_distribution
}
# resource "azurerm_lb_outbound_rule" "lb" {
#   for_each = local.ilb_be
# 	name                                      = "${each.value.app}-out-rule"
# 	resource_group_name                       = each.value.rg
# 	loadbalancer_id                           = try(azurerm_lb.ilb[each.value.lb].id, azurerm_lb.elb[each.value.lb].id)
# 	protocol                                  = each.value.out_rule_protocol
# 	backend_address_pool_id                   = azurerm_lb_backend_address_pool.lb["${each.value.lb}-${each.value.app}"].id
# 	enable_tcp_reset                          = each.value.tcp_reset
#   disableOutboundSNAT                       = true
# 	allocated_outbound_ports                  = each.value.out_ports
# 	frontend_ip_configuration {
# 		name                                    = "${each.value.app}-frontend"
# 	}
# }
resource "azurerm_network_interface_backend_address_pool_association" "lb" {
  for_each = {
    for association in local.bap_associations : association.ref => association
  }
  network_interface_id                      = each.value.nic_id
  ip_configuration_name                     = each.value.ip_configuration_name
  backend_address_pool_id                   = azurerm_lb_backend_address_pool.lb[each.value.be_ref].id
}