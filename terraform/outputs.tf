output "public_ip_address" {
  description = "Publiczny adres IP glownej maszyny"
  value       = azurerm_public_ip.myterraformpublicip.ip_address
}

output "agent_private_ip" {
  description = "Prywatny adres IP maszyny agent"
  value       = azurerm_network_interface.agent_nic.private_ip_address
}

