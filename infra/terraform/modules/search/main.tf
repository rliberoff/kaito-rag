resource "azurerm_search_service" "search" {
  resource_group_name          = var.resource_group_name
  location                     = var.location
  name                         = var.name
  sku                          = var.sku
  semantic_search_sku          = var.sku_semantic_search
  local_authentication_enabled = false
  tags                         = var.tags
}

resource "azurerm_role_assignment" "search_reader" {
  scope                = azurerm_search_service.search.id
  role_definition_name = "Search Index Data Reader"
  principal_id         = var.principal_id
}

resource "azurerm_role_assignment" "search_data_contributor" {
  scope                = azurerm_search_service.search.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = var.principal_id
}

resource "azurerm_role_assignment" "search_service_contributor" {
  scope                = azurerm_search_service.search.id
  role_definition_name = "Search Service Contributor"
  principal_id         = var.principal_id
}
