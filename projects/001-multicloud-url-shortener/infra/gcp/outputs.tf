output "service_url" {
  description = "Public HTTPS URL of the Cloud Run URL shortener service"
  value       = google_cloud_run_v2_service.app.uri
}

output "artifact_registry_repo" {
  description = "Artifact Registry Docker repository path"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.repo.repository_id}"
}

output "firestore_database" {
  description = "Dedicated Firestore database name"
  value       = google_firestore_database.db.name
}

output "bigquery_table" {
  description = "Fully qualified BigQuery analytics table ID"
  value       = "${var.project_id}.${google_bigquery_dataset.analytics.dataset_id}.${google_bigquery_table.clicks.table_id}"
}
