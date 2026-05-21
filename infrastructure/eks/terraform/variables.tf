variable "region" {
  description = "AWS region for EKS (India)."
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = null
}

variable "node_count" {
  description = "Number of worker nodes. Must remain 1 (horizontal scaling disabled)."
  type        = number
  default     = 1

  validation {
    condition     = var.node_count == 1
    error_message = "Horizontal scaling is disabled. node_count must be 1."
  }
}

variable "node_instance_type" {
  description = "EC2 instance type for the node group (vertical sizing control). Default fits 10 vCPU / 20 GiB workload total."
  type        = string
  default     = "m6i.4xlarge"
}

variable "tags" {
  description = "Tags to apply to AWS resources."
  type        = map(string)
  default = {
    workload = "stackguard"
    managed  = "terraform"
  }
}
