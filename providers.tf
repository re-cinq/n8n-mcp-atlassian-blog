# Main provider that uses service account impersonation
provider "google" {
  project                     = var.project_id
  region                      = var.region
  impersonate_service_account = "terraform-sa@${var.project_id}.iam.gserviceaccount.com"
}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

# Get current client configuration for kubernetes provider
data "google_client_config" "default" {}