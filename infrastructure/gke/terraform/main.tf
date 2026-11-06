# StackGuard reads the GCP project ID from the metadata server
# (http://metadata.google.internal/computeMetadata/v1/...?recursive=true with Metadata-Flavor: Google).
# Nodes use GCE_METADATA so pods can reach that endpoint (do not block 169.254.169.254/32).
resource "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.region

  remove_default_node_pool = true
  initial_node_count       = 1
  min_master_version       = var.kubernetes_version

  resource_labels = var.labels
}

resource "google_container_node_pool" "this" {
  name     = "${var.cluster_name}-np"
  location = var.region
  cluster  = google_container_cluster.this.name

  # Autoscaling OFF — do not add an autoscaling {} block. Vertical size only.
  node_count = var.node_count

  node_config {
    machine_type = var.node_machine_type
    # Ubuntu only. Do not use Container-Optimized OS (COS) or Windows.
    image_type = "UBUNTU_CONTAINERD"
    labels = merge(var.labels, {
      "stackguard.io/os"       = "ubuntu"
      "stackguard.io/workload" = "stackguard"
    })

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    # Expose GCE metadata to pods so StackGuard can detect project ID.
    # GKE_METADATA (Workload Identity) can hide fields the app needs.
    workload_metadata_config {
      mode = "GCE_METADATA"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
