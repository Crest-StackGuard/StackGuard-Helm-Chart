data "azurerm_client_config" "current" {}

output "resource_group_name" {
  description = "Resource group containing the AKS cluster."
  value       = azurerm_resource_group.this.name
}

output "aks_cluster_name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.this.name
}

output "aks_fqdn" {
  description = "AKS API server FQDN."
  value       = azurerm_kubernetes_cluster.this.fqdn
}

output "subscription_id" {
  description = "Azure subscription ID (also readable by pods via IMDS)."
  value       = data.azurerm_client_config.current.subscription_id
}
