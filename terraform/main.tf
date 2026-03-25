terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# 1. Resource Group
resource "azurerm_resource_group" "myterraformgroup" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    environment = "Terraform Demo"
  }
}

# 2. Virtual Network
resource "azurerm_virtual_network" "myterraformnetwork" {
  name                = "Group8net"
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.myterraformgroup.location
  resource_group_name = azurerm_resource_group.myterraformgroup.name

  tags = {
    environment = "Terraform Demo"
  }
}

# 3. Subnet
resource "azurerm_subnet" "myterraformsubnet" {
  name                 = "group8Subnet"
  resource_group_name  = azurerm_resource_group.myterraformgroup.name
  virtual_network_name = azurerm_virtual_network.myterraformnetwork.name
  address_prefixes     = var.subnet_address_prefix
}

# 4. Public IP
resource "azurerm_public_ip" "myterraformpublicip" {
  name                = "group8PublicIP"
  location            = azurerm_resource_group.myterraformgroup.location
  resource_group_name = azurerm_resource_group.myterraformgroup.name
  allocation_method   = "Static"

  tags = {
    environment = "Terraform Demo"
  }
}

# 5. Network Security Group
resource "azurerm_network_security_group" "myterraformnsg" {
  name                = "group8NetworkSecurityGroup"
  location            = azurerm_resource_group.myterraformgroup.location
  resource_group_name = azurerm_resource_group.myterraformgroup.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "Terraform Demo"
  }
}

# 6. Network Interface
resource "azurerm_network_interface" "myterraformnic" {
  name                = "group8NIC"
  location            = azurerm_resource_group.myterraformgroup.location
  resource_group_name = azurerm_resource_group.myterraformgroup.name

  ip_configuration {
    name                          = "group8NicConfiguration"
    subnet_id                     = azurerm_subnet.myterraformsubnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.myterraformpublicip.id
  }

  tags = {
    environment = "Terraform Demo"
  }
}

# 7. Powiązanie NSG z interfejsem sieciowym
resource "azurerm_network_interface_security_group_association" "nic_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.myterraformnic.id
  network_security_group_id = azurerm_network_security_group.myterraformnsg.id
}

# 8. Storage Account dla diagnostyki
resource "random_id" "randomId" {
  keepers = {
    resource_group = azurerm_resource_group.myterraformgroup.name
  }
  byte_length = 8
}

resource "azurerm_storage_account" "mystorageaccount" {
  name                     = "diag${random_id.randomId.hex}"
  resource_group_name      = azurerm_resource_group.myterraformgroup.name
  location                 = azurerm_resource_group.myterraformgroup.location
  account_replication_type = "LRS"
  account_tier             = "Standard"

  tags = {
    environment = "Terraform Demo"
  }
}

# 9. Linux Virtual Machine
resource "azurerm_linux_virtual_machine" "myterraformvm" {
  name                  = "group8VM"
  location              = azurerm_resource_group.myterraformgroup.location
  resource_group_name   = azurerm_resource_group.myterraformgroup.name
  network_interface_ids = [azurerm_network_interface.myterraformnic.id]
  size                  = var.vm_size

  os_disk {
    name                 = "group8Disk"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  computer_name                   = "group8vm"
  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.mystorageaccount.primary_blob_endpoint
  }

  tags = {
    environment = "Terraform Demo"
  }
}

output "public_ip_address" {
  value = azurerm_public_ip.myterraformpublicip.ip_address
}

# --- DRUGA MASZYNA WIRTUALNA (AGENT) ---

# 11. Publiczne IP dla drugiej maszyny
resource "azurerm_public_ip" "agent_public_ip" {
  name                = "group8AgentPublicIP"
  location            = azurerm_resource_group.myterraformgroup.location
  resource_group_name = azurerm_resource_group.myterraformgroup.name
  allocation_method   = "Static"
}

# 12. Interfejs sieciowy dla drugiej maszyny
resource "azurerm_network_interface" "agent_nic" {
  name                = "group8AgentNIC"
  location            = azurerm_resource_group.myterraformgroup.location
  resource_group_name = azurerm_resource_group.myterraformgroup.name

  ip_configuration {
    name                          = "agentNicConfiguration"
    subnet_id                     = azurerm_subnet.myterraformsubnet.id # Ta sama podsieć!
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.agent_public_ip.id
  }
}

# 13. Powiązanie Security Group (otwarte porty) z drugą maszyną
resource "azurerm_network_interface_security_group_association" "agent_nic_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.agent_nic.id
  network_security_group_id = azurerm_network_security_group.myterraformnsg.id
}

# 14. Druga maszyna wirtualna (Ubuntu)
resource "azurerm_linux_virtual_machine" "agent_vm" {
  name                  = "group8AgentVM"
  location              = azurerm_resource_group.myterraformgroup.location
  resource_group_name   = azurerm_resource_group.myterraformgroup.name
  network_interface_ids = [azurerm_network_interface.agent_nic.id]
  size                  = var.vm_size_agent

  os_disk {
    name                 = "group8AgentDisk"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  computer_name                   = "group8agent"
  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.mystorageaccount.primary_blob_endpoint
  }
}

# --- AKTUALIZACJA GENERATORA INVENTORY ---

# 15. Zaktualizowany plik dla Ansible (obsługuje teraz Dwie maszyny)
resource "local_file" "ansible_inventory" {
  content = <<-EOT
  [azure_vm]
  ${azurerm_public_ip.myterraformpublicip.ip_address} private_ip=${azurerm_network_interface.myterraformnic.private_ip_address}

  [agent_vm]
  ${azurerm_public_ip.agent_public_ip.ip_address} private_ip=${azurerm_network_interface.agent_nic.private_ip_address}

  [all:vars]
  ansible_user=${var.admin_username}
  ansible_ssh_private_key_file=terraform/.ssh/id_rsa
  ansible_ssh_common_args="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null"
  EOT

  filename = "../ansible/inventory.ini"
}

output "agent_private_ip" {
  value = azurerm_network_interface.agent_nic.private_ip_address
}