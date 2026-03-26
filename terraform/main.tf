terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm" # Provider do zarzadzania zasobami Azure.
      version = "~> 3.0"            # Blokada na glowna wersje 3.x.
    }
    random = {
      source  = "hashicorp/random" # Provider do generowania losowych identyfikatorow.
      version = "~> 3.0"           # Stabilna linia wersji 3.x.
    }
    local = {
      source  = "hashicorp/local" # Provider do generowania plikow lokalnych.
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {} # Wymagany pusty blok inicjalizacji providera AzureRM.
}

# 1. Resource Group
resource "azurerm_resource_group" "myterraformgroup" {
  name     = var.resource_group_name # Nazwa grupy zasobow zdefiniowana w zmiennych.
  location = var.location            # Region Azure, w ktorym tworzone sa zasoby.

  tags = {
    environment = "Terraform Demo" # Tag pomocny przy filtrowaniu zasobow.
  }
}

# 2. Virtual Network
resource "azurerm_virtual_network" "myterraformnetwork" {
  name                = "Group8net"                                      # Nazwa sieci wirtualnej.
  address_space       = var.vnet_address_space                           # Glowny zakres adresow VNet.
  location            = azurerm_resource_group.myterraformgroup.location # Ta sama lokalizacja co RG.
  resource_group_name = azurerm_resource_group.myterraformgroup.name     # Przypiecie VNet do tej samej RG.

  tags = {
    environment = "Terraform Demo" # Ujednolicone tagowanie zasobu.
  }
}

# 3. Subnet
resource "azurerm_subnet" "myterraformsubnet" {
  name                 = "group8Subnet"                                  # Nazwa podsieci wewnatrz VNet.
  resource_group_name  = azurerm_resource_group.myterraformgroup.name    # RG, w ktorej istnieje VNet.
  virtual_network_name = azurerm_virtual_network.myterraformnetwork.name # Powiazanie z utworzona siecia.
  address_prefixes     = var.subnet_address_prefix                       # Zakres IP dla podsieci.
}

# 4. Public IP
resource "azurerm_public_ip" "myterraformpublicip" {
  name                = "group8PublicIP"                                 # Publiczny adres IP dla glownej VM.
  location            = azurerm_resource_group.myterraformgroup.location # Ten sam region co pozostale zasoby.
  resource_group_name = azurerm_resource_group.myterraformgroup.name     # Ten sam kontener zasobow.
  allocation_method   = "Static"                                         # Staly adres IP (nie zmienia sie po restarcie).

  tags = {
    environment = "Terraform Demo" # Ujednolicone tagi projektu.
  }
}

# 5. Network Security Group
resource "azurerm_network_security_group" "myterraformnsg" {
  name                = "group8NetworkSecurityGroup"                     # NSG kontrolujaca ruch do maszyn.
  location            = azurerm_resource_group.myterraformgroup.location # NSG w tym samym regionie.
  resource_group_name = azurerm_resource_group.myterraformgroup.name     # NSG przypisana do tej samej RG.

  security_rule {
    name                       = "SSH"     # Nazwa reguly ruchu SSH.
    priority                   = 1001      # Priorytet (nizsza liczba = wyzszy priorytet).
    direction                  = "Inbound" # Regula dla ruchu przychodzacego.
    access                     = "Allow"   # Zezwolenie na ruch.
    protocol                   = "Tcp"     # SSH dziala po TCP.
    source_port_range          = "*"       # Port zrodlowy dowolny.
    destination_port_range     = "22"      # Otwieramy port SSH.
    source_address_prefix      = "*"       # Dostep z dowolnego adresu zrodlowego.
    destination_address_prefix = "*"       # Dotyczy kazdego adresu docelowego NIC.
  }

  security_rule {
    name                       = "HTTP"    # Nazwa reguly ruchu HTTP.
    priority                   = 1002      # Nizszy priorytet niz SSH.
    direction                  = "Inbound" # Ruch przychodzacy do VM.
    access                     = "Allow"   # Zezwolenie na ruch webowy.
    protocol                   = "Tcp"     # HTTP po TCP.
    source_port_range          = "*"       # Port zrodlowy dowolny.
    destination_port_range     = "80"      # Otwieramy port 80.
    source_address_prefix      = "*"       # Ruch z dowolnego adresu.
    destination_address_prefix = "*"       # Regula dla calego interfejsu docelowego.
  }

  tags = {
    environment = "Terraform Demo" # Tagi zgodne z reszta infrastruktury.
  }
}

# 6. Network Interface
resource "azurerm_network_interface" "myterraformnic" {
  name                = "group8NIC"                                      # Interfejs sieciowy glownej VM.
  location            = azurerm_resource_group.myterraformgroup.location # Region zgodny z VM.
  resource_group_name = azurerm_resource_group.myterraformgroup.name     # RG zawierajaca NIC.

  ip_configuration {
    name                          = "group8NicConfiguration"                 # Nazwa konfiguracji IP NIC.
    subnet_id                     = azurerm_subnet.myterraformsubnet.id      # Podpiecie do utworzonej podsieci.
    private_ip_address_allocation = "Dynamic"                                # Prywatne IP nadawane dynamicznie.
    public_ip_address_id          = azurerm_public_ip.myterraformpublicip.id # Powiazanie z publicznym IP.
  }

  tags = {
    environment = "Terraform Demo" # Tagi ulatwiajace identyfikacje zasobu.
  }
}

# 7. Powiązanie NSG z interfejsem sieciowym
resource "azurerm_network_interface_security_group_association" "nic_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.myterraformnic.id      # NIC, do ktorej podpinamy reguly.
  network_security_group_id = azurerm_network_security_group.myterraformnsg.id # NSG z otwartymi portami.
}

# 8. Storage Account dla diagnostyki
resource "random_id" "randomId" {
  keepers = {
    resource_group = azurerm_resource_group.myterraformgroup.name # Zmiana RG wymusi nowe losowanie.
  }
  byte_length = 8 # Dlugosc losowego fragmentu dla unikalnej nazwy konta storage.
}

resource "azurerm_storage_account" "mystorageaccount" {
  name                     = "diag${random_id.randomId.hex}"                  # Unikalna nazwa wymagana przez Azure.
  resource_group_name      = azurerm_resource_group.myterraformgroup.name     # Konto storage w tej samej RG.
  location                 = azurerm_resource_group.myterraformgroup.location # Konto storage w tym samym regionie.
  account_replication_type = "LRS"                                            # Replikacja lokalna (jeden region).
  account_tier             = "Standard"                                       # Standardowa klasa konta.

  tags = {
    environment = "Terraform Demo" # Tagi projektu.
  }
}

# 9. Linux Virtual Machine
resource "azurerm_linux_virtual_machine" "myterraformvm" {
  name                  = "group8VM"                                       # Nazwa glownej maszyny Linux.
  location              = azurerm_resource_group.myterraformgroup.location # Region wdrozenia VM.
  resource_group_name   = azurerm_resource_group.myterraformgroup.name     # RG, do ktorej VM nalezy.
  network_interface_ids = [azurerm_network_interface.myterraformnic.id]    # Podpiecie VM do NIC.
  size                  = var.vm_size                                      # Rozmiar VM zdefiniowany zmienna.

  os_disk {
    name                 = "group8Disk"      # Nazwa dysku systemowego.
    caching              = "ReadWrite"       # Buforowanie odczytu i zapisu.
    storage_account_type = "StandardSSD_LRS" # Typ dysku systemowego.
  }

  source_image_reference {
    publisher = "Canonical"                    # Wydawca obrazu Ubuntu.
    offer     = "0001-com-ubuntu-server-jammy" # Linia obrazu Ubuntu Server Jammy.
    sku       = "22_04-lts"                    # Wersja LTS 22.04.
    version   = "latest"                       # Zawsze najnowszy patch obrazu.
  }

  computer_name                   = "group8vm"         # Hostname widoczny wewnatrz systemu.
  admin_username                  = var.admin_username # Konto administracyjne Linux.
  disable_password_authentication = true               # Wylaczenie logowania haslem (tylko SSH key).

  admin_ssh_key {
    username   = var.admin_username            # Uzytkownik, dla ktorego dodajemy klucz.
    public_key = file(var.ssh_public_key_path) # Wczytanie klucza publicznego z pliku.
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.mystorageaccount.primary_blob_endpoint # Miejsce zapisu logow startu VM.
  }

  tags = {
    environment = "Terraform Demo" # Tagi projektu.
  }
}

# --- DRUGA MASZYNA WIRTUALNA (AGENT) ---

# 11. Publiczne IP dla drugiej maszyny
resource "azurerm_public_ip" "agent_public_ip" {
  name                = "group8AgentPublicIP"                            # Publiczny adres IP dla maszyny agent.
  location            = azurerm_resource_group.myterraformgroup.location # Region taki sam jak reszta infrastruktury.
  resource_group_name = azurerm_resource_group.myterraformgroup.name     # Przynaleznosc do tej samej RG.
  allocation_method   = "Static"                                         # Staly publiczny adres.
}

# 12. Interfejs sieciowy dla drugiej maszyny
resource "azurerm_network_interface" "agent_nic" {
  name                = "group8AgentNIC"                                 # NIC dla maszyny agent.
  location            = azurerm_resource_group.myterraformgroup.location # Region zgodny z VM agent.
  resource_group_name = azurerm_resource_group.myterraformgroup.name     # RG dla interfejsu.

  ip_configuration {
    name                          = "agentNicConfiguration"              # Nazwa konfiguracji IP dla agent NIC.
    subnet_id                     = azurerm_subnet.myterraformsubnet.id  # Ta sama podsiec co glowna VM.
    private_ip_address_allocation = "Dynamic"                            # Dynamiczne prywatne IP.
    public_ip_address_id          = azurerm_public_ip.agent_public_ip.id # Podpiecie dedykowanego publicznego IP.
  }
}

# 13. Powiązanie Security Group (otwarte porty) z drugą maszyną
resource "azurerm_network_interface_security_group_association" "agent_nic_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.agent_nic.id           # NIC maszyny agent.
  network_security_group_id = azurerm_network_security_group.myterraformnsg.id # Wspolna NSG dla obu maszyn.
}

# 14. Druga maszyna wirtualna (Ubuntu)
resource "azurerm_linux_virtual_machine" "agent_vm" {
  name                  = "group8AgentVM"                                  # Nazwa maszyny agent.
  location              = azurerm_resource_group.myterraformgroup.location # Region wdrozenia.
  resource_group_name   = azurerm_resource_group.myterraformgroup.name     # RG maszyny agent.
  network_interface_ids = [azurerm_network_interface.agent_nic.id]         # Podpiecie do agent NIC.
  size                  = var.vm_size_agent                                # Rozmiar VM agent z osobnej zmiennej.

  os_disk {
    name                 = "group8AgentDisk" # Nazwa dysku systemowego agenta.
    caching              = "ReadWrite"       # Buforowanie dysku systemowego.
    storage_account_type = "StandardSSD_LRS" # Typ dysku systemowego.
  }

  source_image_reference {
    publisher = "Canonical"                    # Wydawca obrazu.
    offer     = "0001-com-ubuntu-server-jammy" # Ubuntu Server Jammy.
    sku       = "22_04-lts"                    # Ubuntu 22.04 LTS.
    version   = "latest"                       # Najnowsza poprawka obrazu.
  }

  computer_name                   = "group8agent"      # Hostname VM agent.
  admin_username                  = var.admin_username # Konto administracyjne.
  disable_password_authentication = true               # Tylko logowanie kluczem SSH.

  admin_ssh_key {
    username   = var.admin_username            # Konto, do ktorego przypisujemy klucz.
    public_key = file(var.ssh_public_key_path) # Klucz publiczny z lokalnego pliku.
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.mystorageaccount.primary_blob_endpoint # Zapis logow bootowania.
  }
}

