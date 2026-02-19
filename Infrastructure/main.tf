# ─────────────────────────────────────────
# DATA SOURCES
# ─────────────────────────────────────────
data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

# ─────────────────────────────────────────
# RESOURCE GROUP
# ─────────────────────────────────────────
resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.project_name}-${var.environment}"
  location = var.location

  tags = {
    environment = var.environment
    project     = var.project_name
    managed_by  = "terraform"
  }
}

# ─────────────────────────────────────────
# AZURE SQL SERVER
# ─────────────────────────────────────────
resource "azurerm_mssql_server" "sql_server" {
  name                         = "sql-${var.project_name}-${var.environment}"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = var.sql_admin_password

  tags = azurerm_resource_group.rg.tags
}

# ─────────────────────────────────────────
# AZURE SQL DATABASE
# ─────────────────────────────────────────
resource "azurerm_mssql_database" "sql_db" {
  name        = "db-${var.project_name}-${var.environment}"
  server_id   = azurerm_mssql_server.sql_server.id
  sku_name    = "Basic" # cheapest tier — good for learning
  max_size_gb = 2

  tags = azurerm_resource_group.rg.tags
}

# ─────────────────────────────────────────
# SQL FIREWALL — Allow Azure Services
# ─────────────────────────────────────────
resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.sql_server.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# ─────────────────────────────────────────
# APP SERVICE PLAN
# ─────────────────────────────────────────
resource "azurerm_service_plan" "app_plan" {
  name                = "plan-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "B1" # Basic tier — cheapest for learning

  tags = azurerm_resource_group.rg.tags
}

# ─────────────────────────────────────────
# APP SERVICE (Node.js Web App)
# ─────────────────────────────────────────
resource "azurerm_linux_web_app" "web_app" {
  name                = "app-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  service_plan_id     = azurerm_service_plan.app_plan.id

  # Enable Managed Identity so app can access Key Vault
  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      node_version = var.node_version
    }
    always_on = false # must be false for Basic tier
  }

  # App settings — reads secrets from Key Vault at runtime
  app_settings = {
    "WEBSITE_NODE_DEFAULT_VERSION" = "~18"
    "DB_SERVER"                    = azurerm_mssql_server.sql_server.fully_qualified_domain_name
    "DB_NAME"                      = azurerm_mssql_database.sql_db.name
    "DB_USERNAME"                  = var.sql_admin_username
    "DB_PASSWORD"                  = var.sql_admin_password
    "NODE_ENV"                     = var.environment
  }

  tags = azurerm_resource_group.rg.tags
}

# ─────────────────────────────────────────
# KEY VAULT
# ─────────────────────────────────────────
resource "azurerm_key_vault" "kv" {
  name                = "kv-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Allow SP (Terraform) to manage secrets
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get", "List", "Set", "Delete", "Purge"
    ]
  }

  # Allow Web App Managed Identity to read secrets
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_linux_web_app.web_app.identity[0].principal_id

    secret_permissions = [
      "Get", "List"
    ]
  }

  tags = azurerm_resource_group.rg.tags
}

# ─────────────────────────────────────────
# KEY VAULT SECRETS
# ─────────────────────────────────────────
resource "azurerm_key_vault_secret" "db_password" {
  name         = "db-password"
  value        = var.sql_admin_password
  key_vault_id = azurerm_key_vault.kv.id
}

resource "azurerm_key_vault_secret" "db_connection_string" {
  name         = "db-connection-string"
  value        = "Server=${azurerm_mssql_server.sql_server.fully_qualified_domain_name};Database=${azurerm_mssql_database.sql_db.name};User Id=${var.sql_admin_username};Password=${var.sql_admin_password};Encrypt=true;"
  key_vault_id = azurerm_key_vault.kv.id
}