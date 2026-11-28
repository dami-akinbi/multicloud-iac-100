variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "damis-project-01"
}

variable "region" {
  description = "GCP deployment region"
  type        = string
  default     = "us-central1"
}

variable "app_name" {
  description = "Base name for Project 001 GCP resources"
  type        = string
  default     = "url-shortener-001"
}

variable "image_uri" {
  description = "Container image URI built in Artifact Registry (falls back to public hello image during PR plans)"
  type        = string
  default     = ""
}
