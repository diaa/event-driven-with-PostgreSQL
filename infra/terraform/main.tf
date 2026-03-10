locals {
  prefix = "${var.project_name}-${var.environment}"
}

module "azure_stack" {
  source = "./modules/azure_stack"
  count  = var.deployment_target == "azure" ? 1 : 0

  prefix                  = local.prefix
  location                = var.azure_location
  postgres_admin_username = var.postgres_admin_username
  postgres_admin_password = var.postgres_admin_password
  postgres_sku_name       = var.azure_postgres_sku_name
  postgres_storage_mb     = var.azure_postgres_storage_mb
  postgres_version        = var.azure_postgres_version
  vm_instance_count       = var.azure_vm_instance_count
  vm_size                 = var.azure_vm_size
  vm_admin_username       = var.azure_vm_admin_username
  vm_admin_ssh_public_key = var.azure_vm_admin_ssh_public_key
  admin_cidr              = var.azure_admin_cidr
  enable_key_vault        = var.azure_enable_key_vault
  enable_vnet_peering     = var.azure_enable_vnet_peering
  remote_vnet_id          = var.azure_remote_vnet_id
}

module "aws_stack" {
  source = "./modules/aws_stack"
  count  = var.deployment_target == "aws" ? 1 : 0

  prefix                  = local.prefix
  region                  = var.aws_region
  postgres_admin_username = var.postgres_admin_username
  postgres_admin_password = var.postgres_admin_password
}
