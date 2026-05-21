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

  node_count = var.node_count

  node_config {
    machine_type = var.node_machine_type
    labels       = var.labels

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
