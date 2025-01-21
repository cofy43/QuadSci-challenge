variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
}

variable "zone" {
  description = "The GCP zone"
  type        = string
}

variable "vertex_ia_admin_members" {
  description = "List of members with admin access to Vertex AI instance"
  type        = list(string)
}

variable "vertex_ia_user_members" {
  description = "List of members with viewer access to Vertex AI instance"
  type        = list(string)
}
variable "cloud_run_admin_members" {
  description = "List of members with admin access to the Cloud Run service"
  type        = list(string)
}

variable "cloud_run_invoker_members" {
  description = "List of members with viewer access to the Cloud Run service"
  type        = list(string)
}