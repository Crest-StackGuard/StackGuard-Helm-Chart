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
  description = "EC2 instance type for the node group (vertical sizing only — never add nodes or app pods). Default 8 vCPU, 16 GiB RAM."
  type        = string
  default     = "c6i.2xlarge"
}

variable "node_ami_id" {
  description = <<-EOT
    Ubuntu EKS worker AMI ID (Canonical). Prefer setting this explicitly — AMI IDs change often.
    Leave null to resolve via node_ami_ssm_parameter (or the default Canonical eks-pro SSM path).
    Must be an Ubuntu EKS AMI — never Amazon Linux / Bottlerocket.
  EOT
  type        = string
  default     = null
}

variable "ubuntu_os_version" {
  description = "Ubuntu OS version used in the default Canonical SSM AMI path (e.g. 24.04)."
  type        = string
  default     = "24.04"
}

variable "node_ami_ssm_parameter" {
  description = <<-EOT
    Full SSM parameter name for the Ubuntu EKS AMI when node_ami_id is null.
    Leave null to build:
      /aws/service/canonical/ubuntu/eks-pro/<ubuntu_os_version>/<cluster_version>/stable/current/amd64/hvm/ebs-gp3/ami-id
    Example:
      /aws/service/canonical/ubuntu/eks-pro/24.04/1.37/stable/current/amd64/hvm/ebs-gp3/ami-id
  EOT
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to AWS resources."
  type        = map(string)
  default = {
    workload = "stackguard"
    managed  = "terraform"
  }
}
