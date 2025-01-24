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

resource "google_project_service" "container" {
  project = var.project_id
  service = "container.googleapis.com"
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
    }
  }
}

######################
# Cloud Run Service  #
######################
resource "google_cloud_run_v2_service" "default" {
  name     = "cloudrun-service"
  location = var.region
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

######################
#   Daks clouster    #
######################
resource "google_service_account" "service-account" {
  account_id   = "dask-service-account"
  display_name = "Dask Service Account"
}

resource "google_project_iam_member" "service_account_role" {
  project = var.project_id
  role    = "roles/container.admin"
  member  = "serviceAccount:${google_service_account.service-account.email}"
}

resource "google_service_account_key" "default" {
  service_account_id = google_service_account.service-account.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

resource "google_project_iam_binding" "dask_helm_deployer_binding" {
  project = var.project_id
  role    = "roles/container.admin"

  members = [
    "serviceAccount:${google_service_account.service-account.email}"
  ]
}

resource "google_container_cluster" "primary" {
  name     = "my-gke-cluster"
  location = var.zone
  initial_node_count = 1

  node_config {
    machine_type = "n1-standard-2"
    disk_size_gb = 100
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    service_account = google_service_account.service-account.email
  }

  network = google_compute_network.vpc_network.id
  subnetwork = google_compute_subnetwork.dask_clouster_subnet.id
  depends_on = [google_project_service.container]
}

resource "google_compute_firewall" "allow_dask_scheduler" {
  name    = "allow-dask-scheduler"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["8786", "8787"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["dask-scheduler"]
}

data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  client_certificate     = base64decode(google_container_cluster.primary.master_auth.0.client_certificate)
  client_key             = base64decode(google_container_cluster.primary.master_auth.0.client_key)
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth.0.cluster_ca_certificate)
}

resource "kubernetes_deployment" "dask-shedulers" {
  metadata {
    name = "dask-shedulers"
  }
  spec {
    replicas = "1"
    selector {
      match_labels = {
        app = "dask-shedulers"
      }
    }
    template {
      metadata {
        labels = {
          app = "dask-shedulers"
        }
      }

      spec {
        container {
          name  = "dask-shedule"
          image = "daskdev/dask:latest"
          args = ["dask-scheduler"]
          env {
            name  = "EXTRA_PIP_PACKAGES"
            value = "gcsfs"
          }
          port {
            name = "tpc-comm"
            container_port = 8786
            protocol = "TCP"
          }
          port {
            name = "http-dashboard"
            container_port = 8787
            protocol = "TCP"
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = "http-dashboard"
            }
            initial_delay_seconds = 10
            period_seconds = 5
          }
          liveness_probe {
            http_get {
              path = "/health"
              port = "http-dashboard"
            }
            initial_delay_seconds = 10
            period_seconds = 5
          }
        }
      }

    }
  }

  depends_on = [ google_container_cluster.primary ]
}

resource "kubernetes_service" "dask-scheduler-service" {
  metadata {
    name = "dask-scheduler-service"
  }
  spec {
    type = "ClusterIP"
    selector = {
      name: "simple"
      component: kubernetes_deployment.dask-shedulers.metadata.0.name
      app: "dask-scheduler"
    }
    port {
      name = "tpc-comm"
      port = 8786
      protocol = "TCP"
      target_port = "tcp-comm"
    }
    port {
      name = "http-dashboard"
      port = 8787
      protocol = "TCP"
      target_port = "http-dashboard"
    }
  }

  depends_on = [ kubernetes_deployment.dask-shedulers ]
}

resource "kubernetes_deployment" "dask-workers" {
  metadata {
    name = "dask-workers"
  }
  spec {
    replicas = "2"
    selector {
      match_labels = {
        app = "dask-worker"
      }
    }
    template {
      metadata {
        labels = {
          app = "dask-worker"
        }
      }

      spec {
        container {
          name  = "dask-worker"
          image = "daskdev/dask:latest"
          args = [  
              "dask-worker", 
              "--name",
              "$(DASK_WORKER_NAME)",
              "--dashboard",
              "--dashboard-address",
              "tcp://dask-scheduler-service:8786"]
          env {
            name  = "EXTRA_PIP_PACKAGES"
            value = "gcsfs"
          }
          port {
            name = "http-dashboard"
            container_port = 8788
            protocol = "TCP"
          }
        }
      }
    }
  }

  depends_on = [ kubernetes_service.dask-scheduler-service ]
}