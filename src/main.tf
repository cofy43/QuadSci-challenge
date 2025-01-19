terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.0.1"
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
  disable_on_destroy = false
}

# Enable Vertex AI API
resource "google_project_service" "vertex_ai" {
  project = var.project_id
  service = "aiplatform.googleapis.com"
  disable_on_destroy = false
  depends_on = [google_project_service.compute_engine]
}

# Enable Notebooks API
resource "google_project_service" "notebooks" {
  project = var.project_id
  service = "notebooks.googleapis.com"
  disable_on_destroy = false
  depends_on = [google_project_service.compute_engine]
}

# Enable Cloud Logging API
resource "google_project_service" "cloud_logging" {
  project = var.project_id
  service = "logging.googleapis.com"
  disable_on_destroy = false
  depends_on = [google_project_service.compute_engine]
}

# Enable IAM API
resource "google_project_service" "iam" {
  project = var.project_id
  service = "iam.googleapis.com"
  disable_on_destroy = false
  depends_on = [google_project_service.compute_engine]
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
  private_ip_google_access = true
}

resource "google_workbench_instance" "instance" {
  name = "workbench-instance"
  location = var.zone
  disable_proxy_access = true

  gce_setup {
    machine_type = "e2-standard-4"
    disable_public_ip = true

    network_interfaces {
      network = google_compute_network.vpc_network.id
      subnet = google_compute_subnetwork.vertex_ai_subnet.id
      nic_type = "GVNIC"
    }
  }
}

# IAM policy to allow specific roles to manage the workbench instance
resource "google_project_iam_binding" "workbench_instance_admin" {
  project = var.project_id
  role    = "roles/notebooks.admin"

  members = var.admin_members
}

resource "google_project_iam_binding" "workbench_instance_user" {
  project = var.project_id
  role    = "roles/notebooks.viewer"

  members = var.user_members
}