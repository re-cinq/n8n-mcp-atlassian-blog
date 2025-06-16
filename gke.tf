resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region  # Autopilot clusters are regional by default
  
  deletion_protection = false

  # Enable Autopilot mode
  enable_autopilot = true

  # Use the default network
  network    = "default"
  subnetwork = "default"

  # Configure IP allocation for pods and services
  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "/17"
    services_ipv4_cidr_block = "/22"
  }

  # Autopilot clusters automatically enable these features:
  # - Workload Identity
  # - Network Policy
  # - HTTP Load Balancing
  # - Horizontal Pod Autoscaling
  # - Node auto-provisioning, auto-scaling, auto-upgrade, and auto-repair
  # - Optimized resource allocation and security configurations
}

