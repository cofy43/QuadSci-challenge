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

variable "admin_members" {
  description = "List of members with admin access to the Workbench instance"
  type        = list(string)
}

variable "user_members" {
  description = "List of members with viewer access to the Workbench instance"
  type        = list(string)
}