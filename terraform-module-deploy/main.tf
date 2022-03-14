terraform {
  required_version = ">= 1.0.0"
  required_providers {
    azurerm = {
      source                = "hashicorp/azurerm"
      version               = ">= 2.78.0"
      configuration_aliases = [azurerm.remote]
    }
  }
}
output "netapp-volumes" {
  value = azurerm_netapp_volume.netapp
} 
output "network-interfaces" {
  value = azurerm_network_interface.nic
} 