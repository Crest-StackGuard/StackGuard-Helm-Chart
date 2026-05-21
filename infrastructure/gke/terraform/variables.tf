variable "project_id" {
  description = "Google Cloud project ID."
  type        = string
}

variable "region" {
  description = "GCP region for GKE (India)."
  type        = string
  default     = "asia-south1"
}

variable "cluster_name" {
  description = "GKE cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "GKE Kubernetes version."
  type        = string
  default     = null
}

variable "node_count" {
  description = "Number of nodes in the node pool. Must remain 1 (horizontal scaling disabled)."
  type        = number
  default     = 1

  validation {
    condition     = var.node_count == 1
    error_message = "Horizontal scaling is disabled. node_count must be 1."
  }
}

variable "node_machine_type" {
  description = "GCE machine type for nodes (vertical sizing control). Default fits 10 vCPU / 20 GiB workload total."
  type        = string
  default     = "n2-standard-16"
}

variable "labels" {
  description = "Labels to apply to GKE resources."
  type        = map(string)
  default = {
    workload = "stackguard"
    managed  = "terraform"
  }
}
