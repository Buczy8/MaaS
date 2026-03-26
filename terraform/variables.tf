variable "resource_group_name" {
  description = "Nazwa grupy zasobów Azure"
  type        = string
  default     = "Group8"
}

variable "location" {
  description = "Lokalizacja geograficzna zasobów"
  type        = string
  default     = "North Europe"
}

variable "vnet_address_space" {
  description = "Przestrzeń adresowa dla wirtualnej sieci (VNet)"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_address_prefix" {
  description = "Prefiks adresacji dla podsieci"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "vm_size" {
  description = "Rozmiar maszyn wirtualnych (serwer)"
  type        = string
  default     = "Standard_B2s"
}

variable "vm_size_agent" {
  description = "Rozmiar maszyn wirtualnych (agent)"
  type        = string
  default     = "Standard_B1s"
}
variable "admin_username" {
  description = "Nazwa użytkownika administratora dla maszyn wirtualnych"
  type        = string
  default     = "group8"

  validation {
    condition     = length(trimspace(var.admin_username)) > 0
    error_message = "admin_username nie moze byc pusty."
  }
}

variable "ssh_public_key_path" {
  description = "Ścieżka do klucza publicznego SSH"
  type        = string
  default     = ".ssh/id_rsa.pub"

  validation {
    condition     = length(trimspace(var.ssh_public_key_path)) > 0
    error_message = "ssh_public_key_path nie moze byc pusta sciezka."
  }
}