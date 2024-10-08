data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

data "azuread_user" "current_user" {
  object_id = data.azurerm_client_config.current.object_id
}

resource "random_id" "random" {
  byte_length = 8
}

locals {
  suffix                       = lower(trimspace(var.use_random_suffix ? substr(lower(random_id.random.hex), 1, 5) : var.suffix))
  name_suffix                  = local.suffix != null ? "-${local.suffix}" : ""
  name_resource_group          = "${var.resource_group_name}${local.name_suffix}"
  name_log_analytics_workspace = "${var.log_analytics_workspace_name}${local.name_suffix}"
  name_vnet                    = "${var.vnet_name}${local.name_suffix}"
  name_subnet                  = "${var.subnet_name}${local.name_suffix}"
  name_cosmos                  = "${var.cosmos_name}${local.name_suffix}"
  name_aks                     = "${var.aks_name}${local.name_suffix}"
  name_appinsights             = "${var.appinsights_name}${local.name_suffix}"
  name_openai                  = "${var.openai_name}${local.name_suffix}"
  name_manage_identity         = "${var.managed_identity_name}${local.name_suffix}"
  name_search                  = "${var.search_name}${local.name_suffix}"
  name_storage_account         = "${var.storage_account_name}${local.suffix}"
  name_bot                     = "${var.bot_name}${local.name_suffix}"
  name_ssk_key                 = "${var.ssh_key_name}${local.name_suffix}"
  name_kv                      = "${var.key_vault_name}${local.name_suffix}"
  name_appcs                   = "${var.appcs_name}${local.name_suffix}"
  name_nsg                     = "${var.nsg_name}${local.name_suffix}"

  aks_admin_group_object_ids = concat(var.aks_admin_group_object_ids, [data.azuread_user.current_user.object_id])

  tags = merge(var.tags, {
    createdAt = "${formatdate("YYYY-MM-DD hh:mm:ss", timestamp())} UTC"
    suffix    = local.suffix
  })
}

resource "azurerm_resource_group" "rg" {
  name     = local.name_resource_group
  location = var.location
  tags     = local.tags

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

module "mi" {
  source              = "./modules/mi"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  name                = local.name_manage_identity
  tags                = local.tags
}

module "log_analytics_workspace" {
  source              = "./modules/log"
  name                = local.name_log_analytics_workspace
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

module "application_insights" {
  source                     = "./modules/appi"
  name                       = local.name_appinsights
  location                   = var.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = module.log_analytics_workspace.id
  tags                       = local.tags
}

module "network" {
  source                     = "./modules/network"
  resource_group_name        = azurerm_resource_group.rg.name
  location                   = azurerm_resource_group.rg.location
  vnet_name                  = local.name_vnet
  vnet_address_space         = var.vnet_address_space
  subnet_name                = local.name_subnet
  subnet_address_space       = var.subnet_address_space
  nsg_name                   = local.name_nsg
  log_analytics_workspace_id = module.log_analytics_workspace.id
  tags                       = local.tags
}

module "openai" {
  source              = "./modules/oai"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.openai_location == null ? var.location : var.openai_location
  name                = local.name_openai
  identity_ids        = [module.mi.id]
  tags                = local.tags
}

module "search" {
  source                       = "./modules/search"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = var.search_location == null ? var.location : var.search_location
  name                         = local.name_search
  sku                          = var.search_sku
  sku_semantic_search          = var.search_sku_semantic_search
  principal_id                 = module.mi.principal_id
  local_authentication_enabled = var.search_local_authentication_enabled
  tags                         = local.tags
}

module "cosmos" {
  source                      = "./modules/cosmos"
  resource_group_name         = azurerm_resource_group.rg.name
  location                    = var.cosmos_location == null ? var.location : var.cosmos_location
  name                        = local.name_cosmos
  database_name               = var.cosmos_database_name
  container_name_chat_history = var.cosmos_container_name_chat_history
  identity_ids                = [module.mi.id]
  tags                        = local.tags
}

module "st" {
  source                   = "./modules/st"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = var.location
  name                     = local.name_storage_account
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  tags                     = local.tags
}

module "bot" {
  source                                   = "./modules/bot"
  name                                     = local.name_bot
  resource_group_name                      = azurerm_resource_group.rg.name
  location                                 = var.bot_location
  sku                                      = var.bot_sku
  type                                     = var.bot_type
  tags                                     = local.tags
  application_insights_id                  = module.application_insights.id
  application_insights_app_id              = module.application_insights.aap_id
  application_insights_instrumentation_key = module.application_insights.instrumentation_key
  backend_endpoint                         = var.bot_backend_endpoint
  msi_name                                 = module.mi.name
  msi_resource_group_name                  = module.mi.resource_group_name
}

module "ssh" {
  source              = "./modules/ssh"
  resource_group_name = azurerm_resource_group.rg.name
  resource_group_id   = azurerm_resource_group.rg.id
  location            = var.location
  name                = local.name_ssk_key
  tags                = local.tags
}

module "aks" {
  source                             = "./modules/aks"
  resource_group_name                = azurerm_resource_group.rg.name
  resource_group_id                  = azurerm_resource_group.rg.id
  name                               = local.name_aks
  location                           = var.location
  sku                                = var.aks_sku
  admin_username                     = var.aks_admin_username
  ssh_public_key                     = module.ssh.public_key
  dns_prefix                         = lower(var.aks_dns_prefix)
  msi_name                           = module.mi.name
  msi_resource_group_name            = module.mi.resource_group_name
  kubernetes_version                 = var.aks_kubernetes_version
  log_analytics_workspace_id         = module.log_analytics_workspace.id
  msi_auth_for_monitoring_enabled    = var.aks_oms_agent_addon_msi_auth_for_monitoring_enabled
  system_node_pool_node_count        = var.aks_system_node_pool_node_count
  system_node_pool_vm_size           = var.aks_system_node_pool_vm_size
  system_node_pool_vnet_subnet_id    = module.network.subnet_id
  use_node_resource_group            = var.aks_use_node_resource_group
  user_node_pool_enable_auto_scaling = var.aks_user_node_pool_enable_auto_scaling
  user_node_pool_name                = var.aks_user_node_pool_name
  user_node_pool_node_count          = var.aks_user_node_pool_node_count
  user_node_pool_node_labels         = var.aks_user_node_pool_node_labels
  user_node_pool_node_taints         = var.aks_user_node_pool_node_taints
  user_node_pool_vm_size             = var.aks_user_node_pool_vm_size
  user_node_pool_vnet_subnet_id      = module.network.subnet_id

  tenant_id              = data.azurerm_client_config.current.tenant_id
  admin_group_object_ids = local.aks_admin_group_object_ids
  tags                   = local.tags
}

# Gets the Resource Group name of the AKS cluster node, which is created during AKS creation.
# The name is dynamically generated by Azure and is not known before the AKS creation.
data "azurerm_resource_group" "node_resource_group" {
  name = module.aks.node_resource_group
}

/* KAITO - Kubernetes AI Toolchain Operator */

locals {
  kaito_identity_name                = var.kaito_use_upstream_version ? module.mi.name : "ai-toolchain-operator-${lower(local.name_aks)}"
  kaito_identity_resource_group_name = var.kaito_use_upstream_version ? module.mi.resource_group_name : data.azurerm_resource_group.node_resource_group.name
}

module "kaito" {
  source                             = "./modules/kaito"
  use_upstream_version               = var.kaito_use_upstream_version
  resource_group_id                  = azurerm_resource_group.rg.id
  resource_group_name                = azurerm_resource_group.rg.name
  tenant_id                          = data.azurerm_client_config.current.tenant_id
  kaito_aks_namespace                = var.kaito_aks_namespace
  aks_node_resource_group_name       = data.azurerm_resource_group.node_resource_group.name
  aks_oidc_issuer_url                = module.aks.oidc_issuer_url
  aks_name                           = module.aks.name
  aks_id                             = module.aks.id
  aks_location                       = module.aks.location
  kaito_instance_type_vm_size        = var.kaito_instance_type_vm_size
  kaito_service_account_name         = var.kaito_service_account_name
  kaito_identity_name                = local.kaito_identity_name
  kaito_identity_resource_group_name = local.kaito_identity_resource_group_name
  kaito_ai_model                     = var.kaito_ai_model
  network_security_group_name        = module.network.nsg_name
  tags                               = local.tags
}

module "kv" {
  source                     = "./modules/kv"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  name                       = local.name_kv
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  principal_id               = module.mi.principal_id
  soft_delete_retention_days = var.key_vault_soft_delete_retention_days
  sku                        = var.key_vault_sku
  tags                       = local.tags
  secrets = [
    {
      name  = "ConnectionStrings:ApplicationInsights"
      value = module.application_insights.connection_string
    },
    {
      name  = "AzureOpenAIOptions:Key"
      value = module.openai.key
    },
    {
      name  = "AzureSearchOptions:Key"
      value = module.search.key
    },
    {
      name  = "CosmosChatHistoryServiceOptions:Key"
      value = module.cosmos.key
    },
    {
      name  = "DirectLineOptions:DirectLineToken"
      value = module.bot.direct_line_key
    },
    {
      name  = "DocumentServiceOptions:BlobStorageConnectionString"
      value = module.st.connection_string
    },
    {
      name  = "MicrosoftAppPassword"
      value = module.bot.password
    },
  ]
}

module "appcs" {
  source                       = "./modules/appcs"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = var.location
  name                         = local.name_appcs
  sku                          = var.appcs_sku
  local_authentication_enabled = var.appcs_local_authentication_enabled
  public_network_access        = var.appcs_public_network_access
  soft_delete_retention_days   = var.appcs_soft_delete_retention_days
  identity_ids                 = [module.mi.id]
  tags                         = local.tags
  secrets = [
    for secret in module.kv.secrets : {
      label     = var.appcs_label
      key       = secret.key
      reference = secret.reference
    }
  ]
  values = [
    {
      label = var.appcs_label
      key   = "AzureSearchOptions:Endpoint"
      value = "https://${local.name_search}.search.windows.net"
    },
    {
      label = var.appcs_label
      key   = "AzureSearchOptions:ResultThreshold"
      value = "2.2"
    },
    {
      label = var.appcs_label
      key   = "AzureOpenAIOptions:Endpoint"
      value = module.openai.endpoint
    },
    {
      label = var.appcs_label
      key   = "AzureOpenAIOptions:EmbeddingsModelDeploymentName"
      value = module.openai.embedding_deployment_name
    },
    {
      label = var.appcs_label
      key   = "CosmosChatHistoryServiceOptions:Endpoint"
      value = module.cosmos.endpoint
    },
    {
      label = var.appcs_label
      key   = "CosmosChatHistoryServiceOptions:ContainerId"
      value = var.cosmos_container_name_chat_history
    },
    {
      label = var.appcs_label
      key   = "CosmosChatHistoryServiceOptions:DatabaseId"
      value = var.cosmos_database_name
    },
    {
      label = var.appcs_label
      key   = "CosmosChatHistoryServiceOptions:MaxRecords"
      value = "3"
    },
    {
      label = var.appcs_label
      key   = "DetailedErrors"
      value = "true"
    },
    {
      label = var.appcs_label
      key   = "DirectLineOptions:DirectLineEndpoint"
      value = module.bot.direct_line_endpoint
    },
    {
      label = var.appcs_label
      key   = "DocumentContentExtractorOptions:MaxTokensPerLine"
      value = "40"
    },
    {
      label = var.appcs_label
      key   = "DocumentContentExtractorOptions:MaxTokensPerParagraph"
      value = "120"
    },
    {
      label = var.appcs_label
      key   = "DocumentServiceOptions:ProgressReportChunksInterval"
      value = "5"
    },
    {
      label = var.appcs_label
      key   = "MicrosoftAppId"
      value = module.bot.app_id
    },
    {
      label = var.appcs_label
      key   = "MicrosoftAppTenantId"
      value = module.bot.tenant_id
    },
    {
      label = var.appcs_label
      key   = "MicrosoftAppType"
      value = module.bot.type
    },
    {
      label = var.appcs_label
      key   = "KaitoInferenceOptions:InferenceEndpoint"
      value = module.kaito.endpoint
    },
    {
      label = var.appcs_label
      key   = "KaitoInferenceOptions:Temperature"
      value = "0.01"
    },
    {
      label = var.appcs_label
      key   = "KaitoInferenceOptions:TopP"
      value = "0.01"
    },
    {
      label = var.appcs_label
      key   = "KaitoInferenceOptions:MaxLength"
      value = "200"
    },
  ]
}
