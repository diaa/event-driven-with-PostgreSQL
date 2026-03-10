variable "prefix" {
  type = string
}

variable "location" {
  type = string
}

variable "postgres_admin_username" {
  type = string
}

variable "postgres_admin_password" {
  type      = string
  sensitive = true
}

variable "postgres_sku_name" {
  description = "Azure PostgreSQL Flexible Server SKU"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgres_storage_mb" {
  description = "Storage size for PostgreSQL Flexible Server"
  type        = number
  default     = 32768
}

variable "postgres_version" {
  description = "PostgreSQL major version"
  type        = string
  default     = "16"
}

variable "vm_instance_count" {
  description = "How many Linux VMs to create for running Docker services"
  type        = number
  default     = 1
}

variable "vm_size" {
  description = "Azure VM size"
  type        = string
  default     = "Standard_D4s_v5"
}

variable "vm_admin_username" {
  description = "Linux admin username for VM access"
  type        = string
  default     = "azureuser"
}

variable "vm_admin_ssh_public_key" {
  description = "SSH public key value for VM login"
  type        = string
}

variable "admin_cidr" {
  description = "CIDR allowed to reach public VM ports"
  type        = string
  default     = "0.0.0.0/0"
}

variable "vnet_cidr" {
  description = "Virtual network CIDR"
  type        = string
  default     = "10.50.0.0/16"
}

variable "app_subnet_cidr" {
  description = "CIDR for VM subnet"
  type        = string
  default     = "10.50.1.0/24"
}

variable "db_subnet_cidr" {
  description = "CIDR for PostgreSQL delegated subnet"
  type        = string
  default     = "10.50.2.0/24"
}

variable "enable_key_vault" {
  description = "Create Azure Key Vault and store demo secrets"
  type        = bool
  default     = true
}

variable "enable_vnet_peering" {
  description = "Enable VNet peering from this VNet to an existing remote VNet"
  type        = bool
  default     = false
}

variable "remote_vnet_id" {
  description = "Resource ID of remote VNet for optional peering"
  type        = string
  default     = ""
}

variable "github_repo_url" {
  description = "HTTPS URL of the GitHub repo to clone on VMs"
  type        = string
}

variable "postgres_fqdn_override" {
  description = "Computed PG FQDN passed from root module (set automatically)"
  type        = string
  default     = ""
}
