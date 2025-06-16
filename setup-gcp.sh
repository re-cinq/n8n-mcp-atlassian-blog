#!/bin/bash

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "\n${BLUE}==== $1 ====${NC}"
}

# Function to wait for user confirmation
wait_for_user() {
    echo -e "\n${YELLOW}Press Enter to complete the above step...${NC}"
    read -r
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

print_step "Google Cloud Platform Setup Script"

# Check prerequisites
print_status "Checking prerequisites..."

if ! command_exists gcloud; then
    print_error "gcloud CLI is not installed. Please install it first: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

if ! command_exists terraform; then
    print_error "Terraform is not installed. Please install it first: https://developer.hashicorp.com/terraform/downloads"
    exit 1
fi

if ! command_exists kubectl; then
    print_error "kubectl is not installed. Please install it first: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

print_status "All prerequisites are met!"

# Get project information
print_step "Project Configuration"

echo "Do you want to create a new Google Cloud project? (y/n)"
read -r create_new_project

if [[ "$create_new_project" =~ ^[Yy]$ ]]; then
    echo "Enter the project name (this will be used as the project ID):"
    read -r PROJECT_NAME
    
    if [[ -z "$PROJECT_NAME" ]]; then
        print_error "Project name cannot be empty"
        exit 1
    fi
    
    print_status "Creating new project: $PROJECT_NAME"
    if ! gcloud projects create "$PROJECT_NAME" --name="$PROJECT_NAME"; then
        print_error "Failed to create project. It might already exist or you don't have permissions."
        exit 1
    fi
    
    export PROJECT_ID="$PROJECT_NAME"
    
    # Set up billing for the new project
    print_step "Setting up Billing Account"
    
    print_status "Retrieving available billing accounts..."
    billing_accounts=$(gcloud billing accounts list --format="value(name,displayName)" 2>/dev/null)
    
    if [[ -z "$billing_accounts" ]]; then
        print_error "No billing accounts found. Please ensure you have access to at least one billing account."
        print_warning "You can create a billing account at: https://console.cloud.google.com/billing"
        exit 1
    fi
    
    echo "Available billing accounts:"
    echo "$billing_accounts" | nl -w2 -s') '
    
    echo "Enter the number of the billing account you want to use:"
    read -r billing_choice
    
    if ! [[ "$billing_choice" =~ ^[0-9]+$ ]]; then
        print_error "Invalid selection. Please enter a number."
        exit 1
    fi
    
    billing_account_id=$(echo "$billing_accounts" | sed -n "${billing_choice}p" | cut -d$'\t' -f1)
    
    if [[ -z "$billing_account_id" ]]; then
        print_error "Invalid billing account selection."
        exit 1
    fi
    
    print_status "Linking project to billing account: $billing_account_id"
    if ! gcloud billing projects link "$PROJECT_ID" --billing-account="$billing_account_id"; then
        print_error "Failed to link billing account to project."
        exit 1
    fi
    
    print_status "Billing account linked successfully!"
else
    echo "Enter your existing Google Cloud project ID:"
    read -r PROJECT_ID
    
    if [[ -z "$PROJECT_ID" ]]; then
        print_error "Project ID cannot be empty"
        exit 1
    fi
    
    # Check if billing is enabled for existing project
    print_status "Checking billing status for project: $PROJECT_ID"
    billing_info=$(gcloud billing projects describe "$PROJECT_ID" --format="value(billingEnabled)" 2>/dev/null)
    
    if [[ "$billing_info" != "True" ]]; then
        print_warning "Billing is not enabled for this project."
        
        print_status "Retrieving available billing accounts..."
        billing_accounts=$(gcloud billing accounts list --format="value(name,displayName)" 2>/dev/null)
        
        if [[ -z "$billing_accounts" ]]; then
            print_error "No billing accounts found. Please ensure you have access to at least one billing account."
            print_warning "You can create a billing account at: https://console.cloud.google.com/billing"
            exit 1
        fi
        
        echo "Available billing accounts:"
        echo "$billing_accounts" | nl -w2 -s') '
        
        echo "Enter the number of the billing account you want to use:"
        read -r billing_choice
        
        if ! [[ "$billing_choice" =~ ^[0-9]+$ ]]; then
            print_error "Invalid selection. Please enter a number."
            exit 1
        fi
        
        billing_account_id=$(echo "$billing_accounts" | sed -n "${billing_choice}p" | cut -d$'\t' -f1)
        
        if [[ -z "$billing_account_id" ]]; then
            print_error "Invalid billing account selection."
            exit 1
        fi
        
        print_status "Linking project to billing account: $billing_account_id"
        if ! gcloud billing projects link "$PROJECT_ID" --billing-account="$billing_account_id"; then
            print_error "Failed to link billing account to project."
            exit 1
        fi
        
        print_status "Billing account linked successfully!"
    else
        print_status "Billing is already enabled for this project."
    fi
fi

# Set project configuration (initial setup)
print_step "Setting up project configuration"

print_status "Setting active project to: $PROJECT_ID"
gcloud config set project "$PROJECT_ID"

# Get user email
export USER_EMAIL=$(gcloud config get-value account 2>/dev/null)
if [[ -z "$USER_EMAIL" ]]; then
    print_warning "Unable to get user email automatically. You may need to authenticate first."
fi

# Export environment variables
export PROJECT_NAME="$PROJECT_ID"

# Source .env file if it exists
if [[ -f ".env" ]]; then
    print_status "Sourcing .env file..."
    source .env
fi

# Authentication
print_step "Authentication Setup"

print_status "Setting up application default credentials..."
print_warning "This will open a browser window for authentication."
wait_for_user

if ! gcloud auth application-default login; then
    print_error "Failed to set up application default credentials"
    exit 1
fi

print_status "Setting up user authentication..."
print_warning "This will open a browser window for authentication."
wait_for_user

if ! gcloud auth login; then
    print_error "Failed to authenticate user"
    exit 1
fi

# Update user email after authentication
export USER_EMAIL=$(gcloud config get-value account 2>/dev/null)
print_status "Using user email: $USER_EMAIL"

# Enable required APIs
print_step "Enabling Required APIs"

apis=(
    "cloudresourcemanager.googleapis.com"
    "iamcredentials.googleapis.com"
    "container.googleapis.com"
    "compute.googleapis.com"
)

for api in "${apis[@]}"; do
    print_status "Enabling $api..."
    if ! gcloud services enable "$api"; then
        print_error "Failed to enable $api"
        exit 1
    fi
done

# Region Selection
print_step "Region Selection"

# Set default region or prompt user
if [[ -z "$REGION" ]]; then
    print_status "No region specified. Setting default region to eu-west1"
    export REGION="eu-west1"
    
    echo "Do you want to use the default region (eu-west1) or choose a different one? (d/c)"
    read -r region_choice
    
    if [[ "$region_choice" =~ ^[Cc]$ ]]; then
        print_status "Retrieving available regions..."
        
        # Get available regions with timeout to prevent hanging
        available_regions=$(timeout 30 gcloud compute regions list --format="value(name)" 2>/dev/null | head -20)
        
        if [[ -z "$available_regions" ]]; then
            print_warning "Unable to retrieve regions list. Using default region: eu-west1"
            export REGION="eu-west1"
        else
            echo "Available regions (showing first 20):"
            echo "$available_regions" | nl -w2 -s') '
            
            echo "Enter the number of the region you want to use (or press Enter for eu-west1):"
            read -r region_selection
            
            if [[ -n "$region_selection" ]] && [[ "$region_selection" =~ ^[0-9]+$ ]]; then
                selected_region=$(echo "$available_regions" | sed -n "${region_selection}p")
                if [[ -n "$selected_region" ]]; then
                    export REGION="$selected_region"
                else
                    print_warning "Invalid selection. Using default region: eu-west1"
                    export REGION="eu-west1"
                fi
            else
                export REGION="eu-west1"
            fi
        fi
    fi
fi

print_status "Using region: $REGION"
gcloud config set compute/region "$REGION"

# Create Terraform service account
print_step "Creating Terraform Service Account"

print_status "Creating terraform-sa service account..."
if ! gcloud iam service-accounts create terraform-sa \
    --description="Terraform service principal" \
    --display-name="Terraform service account"; then
    print_warning "Service account might already exist, continuing..."
fi

# Grant required roles
print_step "Granting Required Roles"

roles=(
    "roles/container.admin"
    "roles/compute.admin"
    "roles/iam.serviceAccountUser"
)

for role in "${roles[@]}"; do
    print_status "Granting $role to terraform-sa..."
    if ! gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:terraform-sa@$PROJECT_ID.iam.gserviceaccount.com" \
        --role="$role"; then
        print_error "Failed to grant $role"
        exit 1
    fi
done

# Grant impersonation rights
print_step "Setting up Service Account Impersonation"

print_status "Granting impersonation rights to $USER_EMAIL..."
if ! gcloud iam service-accounts add-iam-policy-binding \
    "terraform-sa@$PROJECT_ID.iam.gserviceaccount.com" \
    --member="user:$USER_EMAIL" \
    --role="roles/iam.serviceAccountTokenCreator"; then
    print_error "Failed to grant impersonation rights"
    exit 1
fi

# Initialize Terraform
print_step "Initializing Terraform"

# Check for Terraform configuration files in current directory
if [[ -f "providers.tf" ]] || [[ -f "main.tf" ]] || [[ -n "$(ls *.tf 2>/dev/null)" ]]; then
    print_status "Found Terraform files in current directory"
elif [[ -d "terraform" ]]; then
    print_status "Found terraform subdirectory, changing to it"
    cd terraform || exit 1
else
    print_error "No Terraform configuration files found"
    exit 1
fi

print_status "Initializing Terraform..."
if ! terraform init; then
    print_error "Failed to initialize Terraform"
    exit 1
fi

# Create environment variables file
print_step "Creating Terraform Environment Variables File"

# The .tf.env file should be created in the current directory since we're already in the right place
tf_env_file=".tf.env"

# Create new .tf.env file (overwrite if exists)
cat > "$tf_env_file" << EOF
# Generated by setup-gcp.sh on $(date)
export PROJECT_ID="$PROJECT_ID"
export PROJECT_NAME="$PROJECT_NAME"
export REGION="$REGION"
export USER_EMAIL="$USER_EMAIL"
export TF_VAR_project_id="$PROJECT_ID"
export TF_VAR_region="$REGION"
export TF_VAR_cluster_name="n8n-cluster"
export TF_VAR_zone="${REGION}-a"
EOF

print_status "Terraform environment variables saved to $tf_env_file"
print_warning "Run 'source $tf_env_file' to load these variables in future sessions"

# Final instructions
print_step "Setup Complete!"

echo -e "${GREEN}✅ Google Cloud Platform setup completed successfully!${NC}"
echo ""
echo "Next steps:"
echo "1. Review and modify variables.tf file to set your specific configurations"
echo "2. Run 'source .tf.env' to load Terraform variables"
echo "3. Run 'terraform plan' to review the infrastructure changes"
echo "4. Run 'terraform apply' to create the GKE cluster"
echo "5. After cluster creation, run: gcloud container clusters get-credentials n8n-cluster --region=$REGION"
echo ""
echo "Terraform environment variables have been saved to .tf.env"
echo "To load them in future sessions, run: source .tf.env"
