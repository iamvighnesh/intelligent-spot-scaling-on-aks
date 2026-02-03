terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
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
  address_space       = ["10.100.0.0/16"]
  tags                = var.resource_tags
}

resource "azurerm_subnet" "nodes_subnet" {
  name                 = "nodes-subnet"
  resource_group_name  = azurerm_resource_group.aks_rg.name
  virtual_network_name = azurerm_virtual_network.cluster_vnet.name
  address_prefixes     = ["10.100.0.0/22"]
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

  auto_scaler_profile {
    expander                    = "priority"
    balance_similar_node_groups = true
    scan_interval               = "10s"
    max_node_provisioning_time  = "5m"
  }

  storage_profile {
    blob_driver_enabled = true
    disk_driver_enabled = true
  }

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name                 = "default"
    vm_size              = "Standard_D4ds_v4"
    os_sku               = "AzureLinux"
    auto_scaling_enabled = true
    node_count           = 3
    min_count            = 3
    max_count            = 5
    vnet_subnet_id       = azurerm_subnet.nodes_subnet.id

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
  role_definition_name = "Azure Kubernetes Service RBAC Admin"
}

resource "azurerm_kubernetes_cluster_node_pool" "dv4_4ds_pool" {
  name                  = "d4dsv4pool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks_cluster.id
  vm_size               = "Standard_D4ds_v4"
  os_sku                = "AzureLinux"
  priority              = "Spot"
  node_count            = 0
  min_count             = 0
  max_count             = 5
  auto_scaling_enabled  = true
  vnet_subnet_id        = azurerm_subnet.nodes_subnet.id
  eviction_policy       = "Delete"
  tags                  = var.resource_tags

  lifecycle {
    ignore_changes = [
      node_taints
    ]
  }

  depends_on = [
    azurerm_kubernetes_cluster.aks_cluster
  ]
}

resource "azurerm_kubernetes_cluster_node_pool" "dv4_8ds_pool" {
  name                  = "d8dsv4pool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks_cluster.id
  vm_size               = "Standard_D8ds_v4"
  os_sku                = "AzureLinux"
  priority              = "Spot"
  node_count            = 0
  min_count             = 0
  max_count             = 5
  auto_scaling_enabled  = true
  vnet_subnet_id        = azurerm_subnet.nodes_subnet.id
  eviction_policy       = "Delete"
  tags                  = var.resource_tags

  lifecycle {
    ignore_changes = [
      node_taints
    ]
  }

  depends_on = [
    azurerm_kubernetes_cluster.aks_cluster
  ]
}

resource "azurerm_kubernetes_cluster_node_pool" "dv5_4ds_pool" {
  name                  = "d4dsv5pool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks_cluster.id
  vm_size               = "Standard_D4ds_v5"
  os_sku                = "AzureLinux"
  priority              = "Spot"
  node_count            = 0
  min_count             = 0
  max_count             = 5
  auto_scaling_enabled  = true
  vnet_subnet_id        = azurerm_subnet.nodes_subnet.id
  eviction_policy       = "Delete"
  tags                  = var.resource_tags

  lifecycle {
    ignore_changes = [
      node_taints
    ]
  }

  depends_on = [
    azurerm_kubernetes_cluster.aks_cluster
  ]
}

resource "azurerm_kubernetes_cluster_node_pool" "dv5_8ds_pool" {
  name                  = "d8dsv5pool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks_cluster.id
  vm_size               = "Standard_D8ds_v5"
  os_sku                = "AzureLinux"
  priority              = "Spot"
  node_count            = 0
  min_count             = 0
  max_count             = 5
  auto_scaling_enabled  = true
  vnet_subnet_id        = azurerm_subnet.nodes_subnet.id
  eviction_policy       = "Delete"
  tags                  = var.resource_tags

  lifecycle {
    ignore_changes = [
      node_taints
    ]
  }

  depends_on = [
    azurerm_kubernetes_cluster.aks_cluster
  ]
}

resource "azurerm_kubernetes_cluster_node_pool" "dv5_8as_pool" {
  name                  = "d8asv5pool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks_cluster.id
  vm_size               = "Standard_D8as_v5"
  os_sku                = "AzureLinux"
  priority              = "Spot"
  node_count            = 0
  min_count             = 0
  max_count             = 5
  auto_scaling_enabled  = true
  vnet_subnet_id        = azurerm_subnet.nodes_subnet.id
  eviction_policy       = "Delete"
  tags                  = var.resource_tags

  lifecycle {
    ignore_changes = [
      node_taints
    ]
  }

  depends_on = [
    azurerm_kubernetes_cluster.aks_cluster
  ]
}

resource "azurerm_kubernetes_cluster_node_pool" "dv5_4as_pool" {
  name                  = "d4asv5pool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks_cluster.id
  vm_size               = "Standard_D4as_v5"
  os_sku                = "AzureLinux"
  priority              = "Spot"
  node_count            = 0
  min_count             = 0
  max_count             = 5
  auto_scaling_enabled  = true
  vnet_subnet_id        = azurerm_subnet.nodes_subnet.id
  eviction_policy       = "Delete"
  tags                  = var.resource_tags

  lifecycle {
    ignore_changes = [
      node_taints
    ]
  }

  depends_on = [
    azurerm_kubernetes_cluster.aks_cluster
  ]
}
