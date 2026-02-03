terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=4.58.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
      recover_soft_deleted_keys       = true
      recover_soft_deleted_secrets    = true
    }
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "aks_rg" {
  name     = var.resource_group_name
  location = var.resource_group_location
  tags     = var.resource_tags
}

resource "azurerm_virtual_network" "cluster_vnet" {
  name                = var.cluster_vnet_name
  resource_group_name = azurerm_resource_group.aks_rg.name
  location            = azurerm_resource_group.aks_rg.location
  address_space       = ["100.100.0.0/16"]
  tags                = var.resource_tags
}

resource "azurerm_subnet" "nodes_subnet" {
  name                 = "nodes-subnet"
  resource_group_name  = azurerm_resource_group.aks_rg.name
  virtual_network_name = azurerm_virtual_network.cluster_vnet.name
  address_prefixes     = ["100.100.0.0/22"]
}

resource "azurerm_kubernetes_cluster" "aks_cluster" {
  name                = var.cluster_name
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = "1.34"
  sku_tier            = "Standard"

  automatic_upgrade_channel = "patch"
  azure_policy_enabled      = true
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }
  image_cleaner_enabled        = true
  image_cleaner_interval_hours = 24
  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }
  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true

  node_provisioning_profile {
    mode = "Auto"
  }

  storage_profile {
    blob_driver_enabled = true
    disk_driver_enabled = true
  }

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name           = "default"
    vm_size        = "Standard_D4ds_v4"
    os_sku         = "AzureLinux"
    node_count     = 3
    vnet_subnet_id = azurerm_subnet.nodes_subnet.id

    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    pod_cidr            = "192.168.0.0/16"
  }

  tags = var.resource_tags
}

resource "azurerm_role_assignment" "cluster_rbac_admin_role_assignment" {
  principal_id         = data.azurerm_client_config.current.object_id
  scope                = azurerm_kubernetes_cluster.aks_cluster.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
}


resource "azurerm_role_assignment" "cluster_network_contributor_role_assignment" {
  principal_id         = azurerm_kubernetes_cluster.aks_cluster.identity[0].principal_id
  scope                = azurerm_virtual_network.cluster_vnet.id
  role_definition_name = "Network Contributor"
}
