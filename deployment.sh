#!/usr/bin/env bash
# Copyright (c) Syncfusion Inc. All rights reserved.

set -e

# variable declaration
repo_url="https://github.com/sivakumar-devops/k0s-deploy/raw/main/private-cloud.zip"
destination="/manifest"

# Parse command-line arguments
for arg in "$@"; do
  case $arg in
    --storage-account-name=*)
      storage_account_name="${arg#*=}"
      ;;
    --storage-account-key=*)
      storage_account_key="${arg#*=}"
      ;;
    --fileshare-name=*)
      fileshare_name="${arg#*=}"
      ;;
    --app_base_url=*)
      app_base_url="${arg#*=}"
      ;;
  esac
done

# Function to display colored output
function say {
  color=$1
  message=$2
  echo "Info: $(tput setaf $color)$message$(tput sgr0)"
}

# Function to display error message and exit
function handle_error {
  say 1 "Error: $1"
  exit 1
}

# Function to check if a command is available
function command_exists {
  command -v "$1" >/dev/null 2>&1
}

# Function to install zip if not present
function install_zip {
  if ! command_exists zip; then
    say 4 "Installing zip..."
    sudo apt-get update
    sudo apt-get install -y zip
    say 2 "zip installed successfully."
  else
    say 2 "zip is already installed."
  fi
}

# Function to install nginx if not present
function install_nginx {
  if ! command_exists nginx; then
    say 4 "Installing s3fs..."
    sudo apt-get update
    sudo apt-get install -y nginx
    say 2 "nginx installed successfully."
  else
    say 2 "nginx is already installed."
  fi
}

# Function to download and unzip GitHub repository
function download_and_unzip_manifest {
  [ -d "$destination" ] && rm -r "$destination" ; mkdir "$destination" || mkdir "$destination"
  say 4 "Downloading and extracting GitHub repository..."
  curl -sSL $repo_url -o repo.zip
  unzip -qq repo.zip -d $destination
  rm repo.zip
}

# Function to mount fileshare
function update_fileshare_name {
  pvconfig_file="$destination/private-cloud/boldbi/configuration/pvclaim_azure_smb.yaml"
  if [-f "$pvconfig_file"]; then
    sed -i -e "s/^ *shareName: <fileshare>/  shareName: $fileshare_name/" "$pvconfig_file"
  else
    handle_error "Pvcalim file is not availble"
  fi 
  kustomfile="$destination/private-cloud/kustomization.yaml"
  set -i -e "s/^ *#- boldbi/configuration/pvclaim_azure_smb.yaml/  - boldbi/configuration/pvclaim_azure_smb.yaml/" "$kustomfile"
  set -i -e "s/^ *- boldbi/configuration/pvclaim_onpremise.yaml/   #- boldbi/configuration/pvclaim_onpremise.yaml/" "$kustomfile"
}

app_base_url_mapping {
  deploy_file="$destination/private-cloud/boldbi/deployment.yaml"
  set -i -e "s/^ *value: <application_base_url>/  value: $app_base_url/" "$kustomfile"
}

nginx_configuration {
  cluster_ip=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.clusterIP}')
  domain=$(echo "$app_base_url" | sed 's~^https\?://~~')
  nginx_conf="/etc/nginx/sites-available/default"
  # Check if the file exists
  if [ -e "$nginx_conf" ]; then
      # If the file exists, remove it
      rm "$nginx_conf"
  fi

  if [ -n "$app_base_url" ]; then
  echo "
    server {
    listen 80;
    server_name $domain;
    return 301 https://$domain$request_uri;
    }
    server {
            server_name   #domain;
            
            listen 443 ssl;
            ssl_certificate /etc/nginx/sites-available/domain.pem;
            ssl_certificate_key /etc/nginx/sites-available/domain.key;
    location / {
            proxy_pass http://$cluster_ip;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_http_version 1.1;
            proxy_set_header   Upgrade $http_upgrade;
            proxy_set_header   Connection keep-alive;
            proxy_set_header   Host $http_host;
            proxy_cache_bypass $http_upgrade;
            proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header   X-Forwarded-Proto $http_x_forwarded_proto;
            proxy_set_header X-Forwarded-Host $host;
        }
    }" | sudo tee "$nginx_conf"
  else
    # Create the default nginx configuration
    echo "
      server {
          listen 80 default_server;
          listen [::]:80 default_server;
      
          location / {
              proxy_pass http://$cluster_ip;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_http_version 1.1;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection keep-alive;
              proxy_set_header Host $http_host;
              proxy_cache_bypass $http_upgrade;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
              proxy_set_header X-Forwarded-Host $host;
          }
      }" | sudo tee "$nginx_conf"
    fi

    # Provide execution permission to the file
    sudo chmod +x "$nginx_conf"
    nginx -t
    nginx -s reload
}

function show_bold_bi_graphic {
  echo ""
  echo "██████╗   ██████╗  ██╗      ███████╗     ██████╗  ████████╗ "
  echo "██╔══██╗ ██╔═══██╗ ██║      ██╔═══██╗    ██╔══██╗   ╚██╔══╝ "
  echo "██████╔╝ ██║   ██║ ██║      ██║   ██║    ██████╔╝    ██║    "
  echo "██╔══██╗ ██║   ██║ ██║      ██║   ██║    ██╔══██╗    ██║    "
  echo "██████╔╝ ╚██████╔╝ ███████╗ ███████╔╝    ██████╔╝ ████████╗ "
  echo " ╚════╝   ╚═════╝  ╚══════╝  ╚═════╝      ╚════╝   ╚══════╝ " 
  echo ""
}

# Install k0s
function Install_k0s {
  say 4 "Installing k0s..."
  if command_exists k0s; then
    say 2 "k0s is already installed."
  else
    curl -sSLf https://get.k0s.sh | sudo sh
  fi
}

# Start k0s cluster 
function start_k0s {
  if ! k0s kubectl get nodes &> /dev/null; then
    say 4 "Starting k0s cluster..."
    sudo k0s install controller --single &
    sleep 5
    sudo k0s start &
    sleep 10
  fi
}

function install_boldbi {
  install_nginx
  install_zip
  download_and_unzip_manifest
  Install_k0s
  start_k0s

  say 4 "Checking app_base_url provided"
  if [ -n "$app_base_url" ]; then
    app_base_url_mapping
  else
    say 3 "Skipping app_base_url mapping as it is not provided"
  fi

  
  
  if ! k0s kubectl get nodes &> /dev/null; then
    handle_error "k0s cluster is not running."
  fi
  
  if [ -n "$storage_account_name" ] && [ -n "$storage_account_key" ] && [ -n "$fileshare_name" ]; then
    update_fileshare_name
    say 4 "Creating azure secret"
    kubectl create secret generic bold-azure-secret --from-literal azurestorageaccountname=$storage_account_name --from-literal azurestorageaccountkey=$storage_account_key --type=Opaque
  else
    say 3 "Skipping fileshare mounting details are not provided."
  fi
  
  say 4 "Deploying Bold BI application..."
  k0s kubectl apply -k $destination/private-cloud

  show_bold_bi_graphic

  say 2 "Bold BI application deployed successfully!"
  say 4 "You can access "boldbi" on $app_base_url after mapping your machine ip with "$(echo "$app_base_url" | sed 's~^https\?://~~')""
}

install_boldbi
