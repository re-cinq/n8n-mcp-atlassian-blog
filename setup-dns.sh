#!/bin/bash

# Setup script for cross-project DNS access for cert-manager and external-dns
# This script creates the necessary GCP service accounts and IAM permissions

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
DNS_PROJECT_ID=""           # Project containing the DNS zone
K8S_PROJECT_ID=""           # Project containing the GKE cluster
DNS_ZONE_NAME=""            # Name of the Cloud DNS zone (e.g., "re-cinq-com")
DOMAIN_NAME=""              # Domain name (e.g., "re-cinq.com")
NAMESPACE=""                # Kubernetes namespace
VALUES_FILE=""              # Path to Helm values file to update

# Service account names
CERT_MANAGER_SA_NAME="cert-manager-dns01"
EXTERNAL_DNS_SA_NAME="external-dns"

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Setup cross-project DNS access for cert-manager and external-dns"
    echo ""
    echo "Options:"
    echo "  --dns-project-id PROJECT_ID     GCP project containing DNS zone (required)"
    echo "  --k8s-project-id PROJECT_ID     GCP project containing GKE cluster (required)"
    echo "  --dns-zone-name ZONE_NAME       Cloud DNS zone name (required)"
    echo "  --domain-name DOMAIN            Domain name (required)"
    echo "  --namespace NAMESPACE           Kubernetes namespace (default: n8n)"
    echo "  --values-file FILE              Path to Helm values file to update (default: n8n-stack/values.yaml)"
    echo "  -h, --help                      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --dns-project-id my-dns-project --k8s-project-id my-k8s-project \\"
    echo "     --dns-zone-name re-cinq-com --domain-name re-cinq.com \\"
    echo "     --values-file n8n-stack/values-production.yaml"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dns-project-id)
            DNS_PROJECT_ID="$2"
            shift 2
            ;;
        --k8s-project-id)
            K8S_PROJECT_ID="$2"
            shift 2
            ;;
        --dns-zone-name)
            DNS_ZONE_NAME="$2"
            shift 2
            ;;
        --domain-name)
            DOMAIN_NAME="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --values-file)
            VALUES_FILE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$DNS_PROJECT_ID" || -z "$K8S_PROJECT_ID" || -z "$DNS_ZONE_NAME" || -z "$DOMAIN_NAME" ]]; then
    echo -e "${RED}Error: Missing required parameters${NC}"
    show_help
    exit 1
fi

# Set default values
if [[ -z "$NAMESPACE" ]]; then
    NAMESPACE="n8n"
fi

if [[ -z "$VALUES_FILE" ]]; then
    VALUES_FILE="n8n-stack/values.yaml"
fi

# Check if values file exists
if [[ ! -f "$VALUES_FILE" ]]; then
    echo -e "${RED}Error: Values file '$VALUES_FILE' not found${NC}"
    exit 1
fi

echo -e "${BLUE}🔧 Setting up cross-project DNS access${NC}"
echo "DNS Project: $DNS_PROJECT_ID"
echo "K8S Project: $K8S_PROJECT_ID"
echo "DNS Zone: $DNS_ZONE_NAME"
echo "Domain: $DOMAIN_NAME"
echo "Namespace: $NAMESPACE"
echo "Values File: $VALUES_FILE"
echo ""

# Check if required tools are installed
check_requirements() {
    echo -e "${YELLOW}Checking requirements...${NC}"
    
    if ! command -v gcloud &> /dev/null; then
        echo -e "${RED}Error: gcloud CLI is not installed${NC}"
        exit 1
    fi
    
    if ! command -v yq &> /dev/null; then
        echo -e "${RED}Error: yq is required but not installed${NC}"
        echo "Please install yq: brew install yq"
        exit 1
    fi
    
    echo -e "${GREEN}✓ All requirements met${NC}"
}

# Create service account for cert-manager
create_cert_manager_sa() {
    echo -e "${YELLOW}Creating cert-manager service account...${NC}"
    
    # Create service account in DNS project
    gcloud iam service-accounts create $CERT_MANAGER_SA_NAME \
        --display-name="cert-manager DNS01 solver" \
        --description="Service account for cert-manager DNS01 challenge solver" \
        --project=$DNS_PROJECT_ID || true
    
    # Grant DNS admin permissions
    gcloud projects add-iam-policy-binding $DNS_PROJECT_ID \
        --member="serviceAccount:${CERT_MANAGER_SA_NAME}@${DNS_PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/dns.admin"
    
    # Create and download service account key
    gcloud iam service-accounts keys create cert-manager-key.json \
        --iam-account="${CERT_MANAGER_SA_NAME}@${DNS_PROJECT_ID}.iam.gserviceaccount.com" \
        --project=$DNS_PROJECT_ID
    
    echo -e "${GREEN}✓ cert-manager service account created${NC}"
}

# Create service account for external-dns
create_external_dns_sa() {
    echo -e "${YELLOW}Creating external-dns service account...${NC}"
    
    # Create service account in DNS project
    gcloud iam service-accounts create $EXTERNAL_DNS_SA_NAME \
        --display-name="external-dns" \
        --description="Service account for external-dns" \
        --project=$DNS_PROJECT_ID || true
    
    # Grant DNS admin permissions
    gcloud projects add-iam-policy-binding $DNS_PROJECT_ID \
        --member="serviceAccount:${EXTERNAL_DNS_SA_NAME}@${DNS_PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/dns.admin"
    
    # Create and download service account key
    gcloud iam service-accounts keys create external-dns-key.json \
        --iam-account="${EXTERNAL_DNS_SA_NAME}@${DNS_PROJECT_ID}.iam.gserviceaccount.com" \
        --project=$DNS_PROJECT_ID
    
    echo -e "${GREEN}✓ external-dns service account created${NC}"
}

# Update Helm values with service account keys
update_helm_values() {
    echo -e "${YELLOW}Updating Helm values with service account keys...${NC}"
    
    # Check if yq is available
    if ! command -v yq &> /dev/null; then
        echo -e "${RED}Error: yq is required but not installed${NC}"
        echo "Please install yq: brew install yq"
        exit 1
    fi
    
    # Base64 encode the service account keys
    CERT_MANAGER_KEY_B64=$(base64 -i cert-manager-key.json)
    EXTERNAL_DNS_KEY_B64=$(base64 -i external-dns-key.json)
    
    # Create a backup of the values file
    cp "$VALUES_FILE" "$VALUES_FILE.backup"
    
    # Update cert-manager service account key
    yq eval ".certManager.clusterIssuer.dns01.cloudDNS.serviceAccountKey = \"$CERT_MANAGER_KEY_B64\"" -i "$VALUES_FILE"
    
    # Update external-dns service account key
    yq eval ".externalDns.google.serviceAccountKey = \"$EXTERNAL_DNS_KEY_B64\"" -i "$VALUES_FILE"
    
    # Update DNS project ID in values
    yq eval ".certManager.clusterIssuer.dns01.cloudDNS.project = \"$DNS_PROJECT_ID\"" -i "$VALUES_FILE"
    yq eval ".externalDns.google.project = \"$DNS_PROJECT_ID\"" -i "$VALUES_FILE"
    
    # Update domain filters
    yq eval ".externalDns.domainFilters = [\"$DOMAIN_NAME\"]" -i "$VALUES_FILE"
    
    echo -e "${GREEN}✓ Helm values updated with service account keys${NC}"
    echo -e "${BLUE}  Backup created: $VALUES_FILE.backup${NC}"
}

# Verify DNS zone exists
verify_dns_zone() {
    echo -e "${YELLOW}Verifying DNS zone...${NC}"
    
    if ! gcloud dns managed-zones describe $DNS_ZONE_NAME --project=$DNS_PROJECT_ID &>/dev/null; then
        echo -e "${RED}Error: DNS zone '$DNS_ZONE_NAME' not found in project '$DNS_PROJECT_ID'${NC}"
        echo "Available zones:"
        gcloud dns managed-zones list --project=$DNS_PROJECT_ID
        exit 1
    fi
    
    echo -e "${GREEN}✓ DNS zone verified${NC}"
}

# Clean up temporary files
cleanup() {
    echo -e "${YELLOW}Cleaning up temporary files...${NC}"
    rm -f cert-manager-key.json external-dns-key.json
    echo -e "${GREEN}✓ Cleanup completed${NC}"
}

# Display next steps
show_next_steps() {
    echo -e "${GREEN}🎉 Setup completed successfully!${NC}"
    echo ""
    echo -e "${YELLOW}What was done:${NC}"
    echo "1. ✓ Created GCP service accounts for cert-manager and external-dns"
    echo "2. ✓ Generated service account keys"
    echo "3. ✓ Updated Helm values file with base64-encoded service account keys"
    echo "4. ✓ Updated DNS project configuration in values file"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Review the updated values in: $VALUES_FILE"
    echo ""
    echo "2. Enable DNS-01 challenges in your values file by setting:"
    echo "   certManager.clusterIssuer.dns01.enabled: true"
    echo ""
    echo "3. Deploy your Helm chart:"
    echo "   cd helm && ./deploy-helm.sh --production"
    echo ""
    echo "4. The secrets will be automatically created by Helm with the service account keys"
    echo ""
    echo -e "${BLUE}DNS Records and SSL certificates will be automatically managed!${NC}"
    echo ""
    echo -e "${YELLOW}Important files:${NC}"
    echo "  - Backup: $VALUES_FILE.backup"
    echo "  - Updated: $VALUES_FILE"
}

# Main execution
main() {
    check_requirements
    verify_dns_zone
    create_cert_manager_sa
    create_external_dns_sa
    update_helm_values
    cleanup
    show_next_steps
}

# Run main function
main
