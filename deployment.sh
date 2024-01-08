#!/usr/bin/env bash
# Copyright (c) Syncfusion Inc. All rights reserved.

set -e

# Variable declaration
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

# Function to install required packages
function install_packages {
  for package in "$@"; do
    if ! command_exists "$package"; then
      say 4 "Installing $package..."
      sudo apt-get update
      sudo apt-get install -y "$package"
      say 2 "$package installed successfully."
    else
      say 2 "$package is already installed."
    fi
  done
}

# Function to download and unzip GitHub repository
function download_and_unzip_manifest {
  [ -d "$destination" ] && rm -r "$destination"
  mkdir -p "$destination"
  say 4 "Downloading and extracting GitHub repository..."
  curl -sSL "$repo_url" -o repo.zip
  unzip -qq repo.zip -d "$destination"
  rm repo.zip
}

# Function to update fileshare name in configuration
function update_fileshare_name {
  pvconfig_file="$destination/private-cloud/boldbi/configuration/pvclaim_azure_smb.yaml"
  if [ -f "$pvconfig_file" ]; then
    sed -i -e "s/^ *shareName: <fileshare>/  shareName: $fileshare_name/" "$pvconfig_file"
  else
    handle_error "Pvclaim file is not available"
  fi

  kustomfile="$destination/private-cloud/kustomization.yaml"
  #sed -i -e "s/^ *#- boldbi/configuration/pvclaim_azure_smb.yaml/  - boldbi/configuration/pvclaim_azure_smb.yaml/" "$kustomfile"
  sed -i -e "s/^ *#- boldbi\/configuration\/pvclaim_azure_smb\.yaml/  - boldbi\/configuration\/pvclaim_azure_smb.yaml/" "$kustomfile"

  #sed -i -e "s/^ *- boldbi/configuration/pvclaim_onpremise.yaml/   #- boldbi/configuration/pvclaim_onpremise.yaml/" "$kustomfile"
  sed -i -e "s/^ *#- boldbi\/configuration\/pvclaim_onpremise\.yaml/  - boldbi\/configuration\/pvclaim_onpremise.yaml/" "$kustomfile"  
}

# Function to update app_base_url in deployment file
function app_base_url_mapping {
  deploy_file="$destination/private-cloud/boldbi/deployment.yaml"
  sed -i -e "s/^ *value: <application_base_url>/  value: $app_base_url/" "$deploy_file"
}

# Function to configure NGINX
function nginx_configuration {
  cluster_ip=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.clusterIP}')
  domain=$(echo "$app_base_url" | sed 's~^https\?://~~')
  nginx_conf="/etc/nginx/sites-available/default"
  
  # Remove existing nginx configuration file
  [ -e "$nginx_conf" ] && rm "$nginx_conf"
  
  if [ -n "$app_base_url" ]; then
    nginx_conf_content="
    server {
      listen 80;
      server_name $domain;
      return 301 https://$domain$request_uri;
    }

    server {
      server_name $domain;
      listen 443 ssl;
      ssl_certificate /etc/nginx/sites-available/domain.pem;
      ssl_certificate_key /etc/nginx/sites-available/domain.key;

      location / {
        proxy_pass http://$cluster_ip;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host \$http_host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
        proxy_set_header X-Forwarded-Host \$host;
      }
    }"
  else
    nginx_conf_content="
    server {
      listen 80 default_server;
      listen [::]:80 default_server;

      location / {
        proxy_pass http://$cluster_ip;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host \$http_host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
        proxy_set_header X-Forwarded-Host \$host;
      }
    }"
  fi

  echo "$nginx_conf_content" | sudo tee "$nginx_conf"
  sudo chmod +x "$nginx_conf"
  nginx -t
  nginx -s reload
}

# Function to display Bold BI graphic
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

# Function to install k0s
function install_k0s {
  say 4 "Installing k0s..."
  command_exists k0s && say 2 "k0s is already installed." || { curl -sSLf https://get.k0s.sh | sudo sh; }
}

# Function to start k0s cluster
function start_k0s {
  k0s kubectl get nodes &> /dev/null || {
    say 4 "Starting k0s cluster..."
    sudo k0s install controller --single &
    sleep 5
    sudo k0s start &
    sleep 10
  }
}

# Function to install Bold BI
function install_bold_bi {
  install_packages nginx zip
  download_and_unzip_manifest
  install_k0s
  start_k0s

  say 4 "Checking app_base_url provided"
  [ -n "$app_base_url" ] && app_base_url_mapping || say 3 "Skipping app_base_url mapping as it is not provided"
  
  k0s kubectl get nodes &> /dev/null || handle_error "k0s cluster is not running."
  
  [ -n "$storage_account_name" ] && [ -n "$storage_account_key" ] && [ -n "$fileshare_name" ] && {
    update_fileshare_name
    say 4 "Creating azure secret"
    kubectl create secret generic bold-azure-secret --from-literal azurestorageaccountname="$storage_account_name" --from-literal azurestorageaccountkey="$storage_account_key" --type=Opaque
  } || say 3 "Skipping fileshare mounting details as they are not provided."
  
  say 4 "Deploying Bold BI application..."
  k0s kubectl apply -k "$destination/private-cloud"

  show_bold_bi_graphic

  say 2 "Bold BI application deployed successfully!"
  say 4 "You can access 'boldbi' on $app_base_url after mapping your machine IP with "$(echo "$app_base_url" | sed 's~^https\?://~~')""
}

install_bold_bi
