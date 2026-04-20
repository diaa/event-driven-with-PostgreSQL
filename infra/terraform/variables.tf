variable "deployment_target" {
  description = "Target platform: local or azure"
  type        = string
  default     = "local"

  validation {
    condition     = contains(["local", "azure"], var.deployment_target)
    error_message = "deployment_target must be one of: local, azure"
  }
}

variable "project_name" {
  description = "Project prefix"
  type        = string
  default     = "edp-cdc"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "azure_location" {
  description = "Azure location"
  type        = string
  default     = "eastus"
}

variable "azure_vm_instance_count" {
  description = "Number of Linux VMs for self-contained demo services"
  type        = number
  default     = 2
}

variable "azure_vm_size" {
  description = "Azure VM SKU for demo VM(s)"
  type        = string
  default     = "Standard_D4s_v5"
}

variable "azure_vm_admin_username" {
  description = "Linux VM admin username"
  type        = string
  default     = "azureuser"
}

variable "azure_vm_admin_password" {
  description = "Password for Linux VM admin user"
  type        = string
  sensitive   = true
}

variable "azure_vm_admin_ssh_public_key" {
  description = "Optional SSH public key for Linux VM (leave empty to use password only)"
  type        = string
  default     = ""
}

variable "azure_admin_cidr" {
  description = "CIDR that can access VM SSH and demo ports"
  type        = string
  default     = "0.0.0.0/0"
}

variable "azure_postgres_sku_name" {
  description = "Azure PostgreSQL Flexible Server SKU"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "azure_postgres_storage_mb" {
  description = "Azure PostgreSQL storage size"
  type        = number
  default     = 32768
}

variable "azure_postgres_version" {
  description = "Azure PostgreSQL major version"
  type        = string
  default     = "16"
}

variable "azure_enable_key_vault" {
  description = "Create Azure Key Vault and store database secrets"
  type        = bool
  default     = true
}

variable "azure_enable_vnet_peering" {
  description = "Enable optional peering from demo VNet to remote VNet"
  type        = bool
  default     = false
}

variable "azure_remote_vnet_id" {
  description = "Remote VNet resource ID for optional peering"
  type        = string
  default     = ""
}

variable "postgres_admin_username" {
  description = "PostgreSQL admin username"
  type        = string
  default     = "pgadmin"
}

variable "postgres_admin_password" {
  description = "PostgreSQL admin password"
  type        = string
  sensitive   = true
}

variable "github_repo_url" {
  description = "HTTPS URL of the GitHub repo to clone on VMs"
  type        = string
  default     = "https://github.com/diaa/event-driven-with-PostgreSQL.git"
}
