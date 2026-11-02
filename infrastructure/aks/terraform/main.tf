resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.aks_cluster_name}-law"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# StackGuard reads the Azure subscription ID from Instance Metadata Service (IMDS)
# at http://169.254.169.254/metadata/instance/... (header Metadata: true).
# AKS exposes IMDS to pods by default — do not block 169.254.169.254/32 in NetworkPolicy.
resource "azurerm_kubernetes_cluster" "this" {
  name                = var.aks_cluster_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = var.dns_prefix
  kubernetes_version  = var.kubernetes_version
  tags                = var.tags

  default_node_pool {
    name       = "systemnp"
    node_count = var.node_count
    vm_size    = var.node_vm_size

    # Ubuntu only. Do not use Azure Linux, CBL-Mariner, or Windows.
    # Marketplace / CreateUIDefinition: set osSKU=Ubuntu2204 and vmEnableAutoScale=false.
    os_sku  = "Ubuntu2204"
    os_type = "Linux"

    # Autoscaling OFF everywhere (vmEnableAutoScale=false). Grow VM size / pod CPU+RAM only.
    enable_auto_scaling = false

    node_labels = {
      "stackguard.io/os"       = "ubuntu"
      "stackguard.io/workload" = "stackguard"
    }
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    outbound_type     = "loadBalancer"
    load_balancer_sku = "standard"
  }

  identity {
    type = "SystemAssigned"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  }
}
