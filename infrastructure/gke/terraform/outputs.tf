output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.this.name
}

output "region" {
  description = "GCP region."
  value       = var.region
}

output "project_id" {
  description = "Google Cloud project ID."
  value       = var.project_id
}
