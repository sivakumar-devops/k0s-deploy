#!/usr/bin/env bash
# Copyright (c) Syncfusion Inc. All rights reserved.

set -e

# Variable declaration
repo_url="https://github.com/sivakumar-devops/k0s-deploy/raw/main/private-cloud.zip"
destination="/manifest"
storage_account_name="nfssharedstorageaccount"
fileshare_name="sharedfileshare"

# Parse command-line arguments
for arg in "$@"; do
  case $arg in
    # --storage-account-name=*)
      # storage_account_name="${arg#*=}"
      # ;;
    # --fileshare-name=*)
      # fileshare_name="${arg#*=}"
      # ;;
    --folder-name=*)
      folder_name="${arg#*=}"
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
      sudo apt-get install -qq -y "$package"
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

# Function to create a folder in NFS file share.
function create_filshare_folder {
    say 4 "Creating Folder inside the NFS fileshare"
    # Mount NFS file share
    sudo mkdir -p "/mount/$storage_account_name/$fileshare_name"
    sudo mount -t nfs "$storage_account_name.file.core.windows.net:/$storage_account_name/$fileshare_name" "/mount/$storage_account_name/$fileshare_name" -o vers=4,minorversion=1,sec=sys,nconnect=4

    # Create folder
    cd "/mount/$storage_account_name/$fileshare_name" || exit
    sudo mkdir "$folder_name"
    sudo chmod 777 "$folder_name"

    # Display directory listing
    ls -lt

    # Change back to root directory
    cd /

    # Unmount NFS file share
    sudo umount "/mount/$storage_account_name/$fileshare_name"
}

# Function to update fileshare name in configuration
function update_fileshare_name {
  pvconfig_file="$destination/private-cloud/boldbi/configuration/pvclaim_azure_nfs.yaml"
  if [ -f "$pvconfig_file" ]; then
    sed -i -e "s/^ *path: \/<storage_account_name>\/<fileshare_name>\/<folder_name>/   path: \/$storage_account_name\/$fileshare_name\/$folder_name/" "$pvconfig_file"
    sed -i -e "s/^ *server: <storage_account_name>.file.core.windows.net/   server: $storage_account_name.file.core.windows.net/" "$pvconfig_file"
  else
    handle_error "Pvclaim file is not available"
  fi

  kustomfile="$destination/private-cloud/kustomization.yaml"
  sed -i -e "s/^ *#- boldbi\/configuration\/pvclaim_azure_nfs\.yaml/  - boldbi\/configuration\/pvclaim_azure_nfs.yaml/" "$kustomfile"

  sed -i -e "s/^ *- boldbi\/configuration\/pvclaim_onpremise\.yaml/  #- boldbi\/configuration\/pvclaim_onpremise.yaml/" "$kustomfile"
}

# Function to update app_base_url in deployment file
function app_base_url_mapping {
  deploy_file="$destination/private-cloud/boldbi/deployment.yaml"
  sed -i -e "s|^ *value: <application_base_url>|          value: $app_base_url|" "$deploy_file"
}

# Function to configure NGINX
function nginx_configuration {
  cluster_ip=$(k0s kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.clusterIP}')
  domain=$(echo "$app_base_url" | sed 's~^https\?://~~')
  nginx_conf="/etc/nginx/sites-available/default"

  # Remove existing nginx configuration file
  [ -e "$nginx_conf" ] && rm "$nginx_conf"

  if [ -n "$app_base_url" ] && ! [[ $domain =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    nginx_conf_content="
    server {
      listen 80;
      server_name $domain;
      return 301 https://$domain\$request_uri;
    }

    server {
      server_name $domain;
      listen 443 ssl;
      ssl_certificate /etc/ssl/domain.pem;
      ssl_certificate_key /etc/ssl/domain.key;

      proxy_read_timeout 300;
		  proxy_connect_timeout 300;
		  proxy_send_timeout 300;

      location / {
        proxy_pass http://$cluster_ip;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host \$http_host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
      }
    }"
  else
    nginx_conf_content="
    server {
      listen 80 default_server;
      listen [::]:80 default_server;

      proxy_read_timeout 300;
		  proxy_connect_timeout 300;
		  proxy_send_timeout 300;

      location / {
        proxy_pass http://$cluster_ip;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host \$http_host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
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
  install_packages nginx zip nfs-common
  download_and_unzip_manifest
  install_k0s
  start_k0s
  say 4 "Checking app_base_url provided"
  if [ -n "$app_base_url" ]; then
    app_base_url_mapping
  else
      say 3 "Skipping app_base_url mapping as it is not provided"
  fi

  k0s kubectl get nodes &> /dev/null || handle_error "k0s cluster is not running."

  if [ -n "$storage_account_name" ] && [ -n "$folder_name" ] && [ -n "$fileshare_name" ]; then
    create_filshare_folder
    update_fileshare_name
  else
    say 3 "Skipping fileshare mounting details as they are not provided."
  fi

  say 4 "Deploying Bold BI application..."
  k0s kubectl apply -k "$destination/private-cloud"

  show_bold_bi_graphic

  nginx_configuration

  say 2 "Bold BI application deployed successfully!"
  say 4 "You can access 'boldbi' on $app_base_url after mapping your machine IP with "$(echo "$app_base_url" | sed 's~^https\?://~~')""
}

install_bold_bi
