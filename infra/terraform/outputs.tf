output "azure_postgres_fqdn" {
  value       = try(module.azure_stack[0].postgres_fqdn, null)
  description = "Azure PostgreSQL FQDN"
}

output "azure_postgres_database" {
  value       = try(module.azure_stack[0].postgres_database, null)
  description = "Azure PostgreSQL demo database"
}

output "aws_postgres_endpoint" {
  value       = try(module.aws_stack[0].postgres_endpoint, null)
  description = "AWS PostgreSQL endpoint"
}

output "azure_vm_public_ips" {
  value       = try(module.azure_stack[0].vm_public_ips, [])
  description = "Public IPs of Azure Linux VM(s)"
}

output "azure_vm_private_ips" {
  value       = try(module.azure_stack[0].vm_private_ips, [])
  description = "Private IPs of Azure Linux VM(s)"
}

output "azure_vm_names" {
  value       = try(module.azure_stack[0].vm_names, [])
  description = "Azure Linux VM names"
}

output "azure_vm_ssh_commands" {
  value       = try(module.azure_stack[0].ssh_commands, [])
  description = "Ready-to-use SSH commands for Azure Linux VM(s)"
}

output "azure_key_vault_name" {
  value       = try(module.azure_stack[0].key_vault_name, null)
  description = "Azure Key Vault name"
}

output "azure_key_vault_uri" {
  value       = try(module.azure_stack[0].key_vault_uri, null)
  description = "Azure Key Vault URI"
}

output "azure_vnet_id" {
  value       = try(module.azure_stack[0].vnet_id, null)
  description = "Azure demo VNet resource ID"
}

output "azure_app_subnet_id" {
  value       = try(module.azure_stack[0].app_subnet_id, null)
  description = "Azure app subnet ID"
}

output "azure_db_subnet_id" {
  value       = try(module.azure_stack[0].db_subnet_id, null)
  description = "Azure database subnet ID"
}

output "azure_vnet_peering_enabled" {
  value       = try(module.azure_stack[0].vnet_peering_enabled, false)
  description = "Whether optional VNet peering is enabled"
}

output "aws_eks_name" {
  value       = try(module.aws_stack[0].eks_name, null)
  description = "AWS EKS cluster for Kafka/Drasi deployment"
}
