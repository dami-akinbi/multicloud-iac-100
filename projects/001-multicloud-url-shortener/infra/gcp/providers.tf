terraform {
  required_version = ">= 1.9.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.12"
    }
  }

  backend "gcs" {
    bucket = "tfstate-shared-dami-akinbi"
    prefix = "projects/001-multicloud-url-shortener/gcp"
  }
}

provider "google" {
  project = "damis-project-01"
  region  = "us-central1"
}