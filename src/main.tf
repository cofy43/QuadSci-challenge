terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.0.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.35.1"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

########################
#     Google APIs      #
########################

resource "google_project_service" "compute_engine" {
  project = var.project_id
  service = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "vertex_ai" {
  project = var.project_id
  service = "aiplatform.googleapis.com"
  disable_on_destroy = false
  depends_on = [google_project_service.compute_engine]
}

resource "google_project_service" "notebooks" {
  project = var.project_id
  service = "notebooks.googleapis.com"
  disable_on_destroy = false
  depends_on = [google_project_service.compute_engine]
}

resource "google_project_service" "cloud_logging" {
  project = var.project_id
  service = "logging.googleapis.com"
  disable_on_destroy = false
  depends_on = [google_project_service.compute_engine]
}

resource "google_project_service" "iam" {
  project = var.project_id
  service = "iam.googleapis.com"
  disable_on_destroy = false
  depends_on = [google_project_service.compute_engine]
}

resource "google_project_service" "vpc_access" {
  project = var.project_id
  service = "vpcaccess.googleapis.com"
  disable_on_destroy = false
  depends_on = [google_project_service.compute_engine]
}

resource "google_project_service" "cloud_run" {
  project = var.project_id
  service = "run.googleapis.com"
  disable_on_destroy = false
  depends_on = [google_project_service.compute_engine]
}

########################
#     Google VPC       #
########################

resource "google_compute_network" "vpc_network" {
  name                    = "vpc-project-network"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.compute_engine]
}

resource "google_compute_subnetwork" "vertex_ai_subnet" {
  name          = "vertex-instance-subnet"
  ip_cidr_range = "10.1.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc_network.id
  depends_on    = [google_project_service.compute_engine]
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "cloud_run_subnet" {
  name          = "cloudrun-subnet"
  ip_cidr_range = "10.2.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc_network.id
  depends_on    = [google_project_service.compute_engine]
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "dask_clouster_subnet" {
  name          = "daskclouster-subnet"
  ip_cidr_range = "10.3.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc_network.id
  depends_on    = [google_project_service.compute_engine]
  private_ip_google_access = true
}

##########################
# IAM Roles and Policies #
##########################

# IAM policy to Vertex AI
resource "google_project_iam_binding" "workbench_instance_admin" {
  project = var.project_id
  role    = "roles/notebooks.admin"

  members = var.vertex_ia_admin_members
}

resource "google_project_iam_binding" "workbench_instance_user" {
  project = var.project_id
  role    = "roles/notebooks.viewer"

  members = var.vertex_ia_user_members
}

# IAM policy to Cloud Run Service
resource "google_project_iam_binding" "cloud_run_admin_role" {
  project = var.project_id
  role    = "roles/run.admin"

  members  = var.cloud_run_admin_members
}

resource "google_project_iam_binding" "cloud_run_invoker" {
  project  = var.project_id
  role     = "roles/run.invoker"

  members = var.cloud_run_invoker_members
}

######################
# Vertex AI Instance #
######################

resource "google_workbench_instance" "instance" {
  name = "vertex-ai-instance"
  location = var.zone
  disable_proxy_access = true

  gce_setup {
    machine_type = "e2-standard-4"
    disable_public_ip = true

    network_interfaces {
      network = google_compute_network.vpc_network.id
      subnet = google_compute_subnetwork.vertex_ai_subnet.id
    }

    metadata = {
      enable-oslogin = false
      # ssh-key = ""
    }
  }
}

######################
# Cloud Run Service  #
######################
resource "google_cloud_run_v2_service" "default" {
  name     = "cloudrun-service"
  location = "us-central1"
  ingress = "INGRESS_TRAFFIC_INTERNAL_ONLY"

  template {
    containers {
      image = "crccheck/hello-world"
    }
    vpc_access{
      network_interfaces {
        network = google_compute_network.vpc_network.id
        subnetwork = google_compute_subnetwork.cloud_run_subnet.id
      }
      egress = "ALL_TRAFFIC"
    }
  }
}

###################
# Test Vertex AI  #
###################
resource "google_compute_instance" "bastion_host" {
  name         = "bastion-vertex-ai"
  machine_type = "e2-medium"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    network       = google_compute_network.vpc_network.id
    subnetwork    = google_compute_subnetwork.vertex_ai_subnet.id
    access_config {}
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${var.public_ssh_key}"
  }
}

output "bastion_host_private_ip" {
  value = google_compute_instance.bastion_host.network_interface[0].network_ip
}

###################
# Test Cloud Run  #
###################
resource "google_compute_firewall" "allow_internal_ssh" {
  name    = "allow-internal-ssh"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["10.0.1.0/24"]
}

resource "google_compute_firewall" "allow_internal_http" {
  name    = "allow-internal-http"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = ["10.0.1.0/24"]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
}

##################
# Test Cloud run #
##################
resource "google_compute_instance" "cloud_run_instance" {
  name         = "cloud-run-instance"
  machine_type = "e2-medium"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    network       = google_compute_network.vpc_network.id
    subnetwork    = google_compute_subnetwork.cloud_run_subnet.id
    access_config {}
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${var.public_ssh_key}"
  }
}

output "bastion_host_private_ip" {
  value = google_compute_instance.cloud_run_instance.network_interface[0].network_ip
}

