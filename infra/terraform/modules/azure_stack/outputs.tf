output "postgres_fqdn" {
  value = azurerm_postgresql_flexible_server.pg.fqdn
}

output "postgres_database" {
  value = azurerm_postgresql_flexible_server_database.appdb.name
}

output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "vm_public_ips" {
  value = [for pip in azurerm_public_ip.vm : pip.ip_address]
}

output "vm_private_ips" {
  value = [for nic in azurerm_network_interface.vm : nic.private_ip_address]
}

output "vm_names" {
  value = [for vm in azurerm_linux_virtual_machine.vm : vm.name]
}

output "ssh_commands" {
  value = [for pip in azurerm_public_ip.vm : "ssh ${var.vm_admin_username}@${pip.ip_address}"]
}

output "postgres_private_connection_string" {
  value     = "postgresql://${var.postgres_admin_username}:${var.postgres_admin_password}@${azurerm_postgresql_flexible_server.pg.fqdn}:5432/${azurerm_postgresql_flexible_server_database.appdb.name}?sslmode=require"
  sensitive = true
}

output "key_vault_name" {
  value = var.enable_key_vault ? azurerm_key_vault.main[0].name : null
}

output "key_vault_id" {
  value = var.enable_key_vault ? azurerm_key_vault.main[0].id : null
}

output "key_vault_uri" {
  value = var.enable_key_vault ? azurerm_key_vault.main[0].vault_uri : null
}

output "vnet_id" {
  value = azurerm_virtual_network.main.id
}

output "app_subnet_id" {
  value = azurerm_subnet.app.id
}

output "db_subnet_id" {
  value = azurerm_subnet.db.id
}

output "vnet_peering_enabled" {
  value = var.enable_vnet_peering && var.remote_vnet_id != ""
}
