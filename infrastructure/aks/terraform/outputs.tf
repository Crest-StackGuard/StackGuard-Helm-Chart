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
