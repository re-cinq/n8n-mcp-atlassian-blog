variable "project_id" {
  description = "The ID of the Google Cloud project"
  type        = string
  # Read from TF_VAR_project_id environment variable, with no default
  # This will force the user to set it or provide it via command line
}

variable "region" {
  description = "The region where the GKE cluster will be deployed"
  type        = string
  #Read from TF_VAR_region environment variable, with no default
}

variable "zone" {
  description = "The zone where the GKE cluster will be deployed"
  type        = string
  #Read from TF_VAR_zone environment variable, with no default
}

variable "cluster_name" {
  description = "The name of the GKE cluster"
  type        = string
  # Read from TF_VAR_cluster_name environment variable, with no default
  # This will force the user to set it or provide it via command line
}

variable "network" {
  description = "The VPC network to use for the GKE cluster"
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "The subnetwork to use for the GKE cluster"
  type        = string
  default     = "default"
}
