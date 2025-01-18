terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable Compute Engine API to fix future problems
resource "google_project_service" "compute_engine" {
  project = var.project_id
  service = "compute.googleapis.com"
}

resource "google_compute_network" "vpc_network" {
  name                    = "main-vpc-network"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.compute_engine]
}

resource "google_compute_subnetwork" "vertex_ai_subnet" {
  name          = "vertex-ai-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc_network.id
  depends_on    = [google_project_service.compute_engine]
}

resource "google_compute_subnetwork" "cloud_run_subnet" {
  name          = "cloud-run-subnet"
  ip_cidr_range = "10.0.2.0/24"
  region        = var.region
  network       = google_compute_network.vpc_network.id
  depends_on    = [google_project_service.compute_engine]
}

resource "google_compute_subnetwork" "gke_subnet" {
  name          = "gke-subnet"
  ip_cidr_range = "10.0.3.0/24"
  region        = var.region
  network       = google_compute_network.vpc_network.id
  depends_on    = [google_project_service.compute_engine]
}