variable "location" {
  description = "Azure region for all resources (India)."
  type        = string
  default     = "centralindia"
}

variable "resource_group_name" {
  description = "Resource group name."
  type        = string
}

variable "aks_cluster_name" {
  description = "AKS cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version."
  type        = string
  default     = null
}

variable "dns_prefix" {
  description = "DNS prefix for AKS API endpoint."
  type        = string
}

variable "node_count" {
  description = "Number of AKS nodes in the default node pool. Must remain 1 (horizontal scaling disabled)."
  type        = number
  default     = 1

  validation {
    condition     = var.node_count == 1
    error_message = "Horizontal scaling is disabled. node_count must be 1."
  }
}

variable "node_vm_size" {
  description = "AKS node VM size (vertical sizing control). Default D16s_v3 (16 vCPU) fits full Stackguard workload; uses Dsv3 family (not Dsv5)."
  type        = string
  default     = "Standard_D16s_v3"
}

variable "tags" {
  description = "Tags to apply to resources."
  type        = map(string)
  default = {
    workload = "stackguard"
    managed  = "terraform"
  }
}
