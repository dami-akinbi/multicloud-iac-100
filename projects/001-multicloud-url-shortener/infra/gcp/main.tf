locals {
  required_apis = toset([
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "firestore.googleapis.com",
    "bigquery.googleapis.com",
  ])

  effective_image = var.image_uri != "" ? var.image_uri : "us-docker.pkg.dev/cloudrun/container/hello"
}

resource "google_project_service" "apis" {
  for_each           = local.required_apis
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "repo" {
  location      = var.region
  repository_id = var.app_name
  description   = "Container images for Project 001 Multi-Cloud URL Shortener"
  format        = "DOCKER"

  cleanup_policies {
    id     = "keep-recent-3"
    action = "KEEP"
    most_recent_versions {
      keep_count = 3
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_firestore_database" "db" {
  project                     = var.project_id
  name                        = "db-${var.app_name}"
  location_id                 = var.region
  type                        = "FIRESTORE_NATIVE"
  concurrency_mode            = "OPTIMISTIC"
  app_engine_integration_mode = "DISABLED"
  delete_protection_state     = "DELETE_PROTECTION_DISABLED"
  deletion_policy             = "DELETE"

  depends_on = [google_project_service.apis]
}

resource "google_bigquery_dataset" "analytics" {
  project                    = var.project_id
  dataset_id                 = "url_analytics_001"
  friendly_name              = "URL Shortener Edge Click Telemetry (Project 001)"
  description                = "Stores edge redirect telemetry events for 001-multicloud-url-shortener"
  location                   = "US"
  delete_contents_on_destroy = true

  depends_on = [google_project_service.apis]
}

resource "google_bigquery_table" "clicks" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.analytics.dataset_id
  table_id            = "click_events"
  deletion_protection = false

  schema = jsonencode([
    { name = "code", type = "STRING", mode = "REQUIRED", description = "Short link slug" },
    { name = "target_url", type = "STRING", mode = "REQUIRED", description = "Destination URL" },
    { name = "clicked_at", type = "TIMESTAMP", mode = "REQUIRED", description = "UTC click timestamp" },
    { name = "user_agent", type = "STRING", mode = "NULLABLE", description = "HTTP User-Agent header" },
    { name = "referer", type = "STRING", mode = "NULLABLE", description = "HTTP Referer header" },
    { name = "client_ip", type = "STRING", mode = "NULLABLE", description = "Forwarded client IP" },
    { name = "edge_region", type = "STRING", mode = "NULLABLE", description = "Serving edge region" },
    { name = "cloud", type = "STRING", mode = "NULLABLE", description = "Cloud provider identifier" }
  ])
}

resource "google_service_account" "runtime" {
  project      = var.project_id
  account_id   = "sa-${var.app_name}"
  display_name = "Runtime Service Account for ${var.app_name}"
}

resource "google_project_iam_member" "runtime_roles" {
  for_each = toset([
    "roles/datastore.user",
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
    "roles/logging.logWriter",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_cloud_run_v2_service" "app" {
  name                = var.app_name
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    service_account = google_service_account.runtime.email

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    containers {
      image = local.effective_image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name  = "CLOUD_PROVIDER"
        value = "gcp"
      }
      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "FIRESTORE_DATABASE"
        value = google_firestore_database.db.name
      }
      env {
        name  = "FIRESTORE_COLLECTION"
        value = "short_links"
      }
      env {
        name  = "BIGQUERY_DATASET"
        value = google_bigquery_dataset.analytics.dataset_id
      }
      env {
        name  = "BIGQUERY_TABLE"
        value = google_bigquery_table.clicks.table_id
      }
      env {
        name  = "CLOUD_RUN_REGION"
        value = var.region
      }
    }
  }

  depends_on = [
    google_project_service.apis,
    google_project_iam_member.runtime_roles,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  project  = var.project_id
  location = google_cloud_run_v2_service.app.location
  name     = google_cloud_run_v2_service.app.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
