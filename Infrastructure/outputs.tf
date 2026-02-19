output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "sql_server_fqdn" {
  value = azurerm_mssql_server.sql_server.fully_qualified_domain_name
}

output "sql_database_name" {
  value = azurerm_mssql_database.sql_db.name
}

output "web_app_url" {
  value = "https://${azurerm_linux_web_app.web_app.default_hostname}"
}

output "web_app_name" {
  value = azurerm_linux_web_app.web_app.name
}

output "key_vault_name" {
  value = azurerm_key_vault.kv.name
}