# Generator inventory Ansible
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/ansible_inventory.tftpl", {
    azure_vm_public_ip  = azurerm_public_ip.myterraformpublicip.ip_address
    azure_vm_private_ip = azurerm_network_interface.myterraformnic.private_ip_address
    agent_vm_public_ip  = azurerm_public_ip.agent_public_ip.ip_address
    agent_vm_private_ip = azurerm_network_interface.agent_nic.private_ip_address
    ansible_user        = var.admin_username
  })

  filename = "../ansible/inventory.ini"
}

