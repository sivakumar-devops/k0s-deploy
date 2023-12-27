#!/bin/bash

set -e

# Variable declaration.
directory="/mnt/boldbi_data"

# Function to display colored output
function say {
  color=$1
  message=$2
  echo "$(tput setaf $color)$message$(tput sgr0)"
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

# Function to install s3fs if not present
function install_s3fs {
  if ! command_exists s3fs; then
    say 4 "Installing s3fs..."
    sudo apt-get update
    sudo apt-get install -y s3fs
    say 2 "s3fs installed successfully."
  else
    say 2 "s3fs is already installed."
  fi
}

# Function to download and unzip GitHub repository
function download_and_unzip {
  repo_url=$1
  destination=$2

  say 4 "Downloading and extracting GitHub repository..."
  curl -sSL $repo_url -o repo.zip
  unzip -qq repo.zip -d $destination
  rm repo.zip
}


# Function to create a new directory
function create_directory {
  directory=$1
  say 4 "Creating directory: $directory"
  sudo mkdir -p $directory
}

# Function to mount S3 bucket
function mount_s3_bucket {
  directory=$1
  aws_access_key=$2
  aws_secret_access_key=$3
  s3_bucket=$4

  say 4 "Mounting S3 bucket..."
  echo "$aws_access_key:$aws_secret_access_key" > ~/.passwd-s3fs
  chmod 600 ~/.passwd-s3fs
  echo "$s3_bucket $directory fuse.s3fs _netdev,allow_other,use_path_request_style,url=https://s3.amazonaws.com 0 0" | sudo tee -a /etc/fstab
  sudo mount -a
  say 2 "S3 bucket mounted successfully."
}

# Function to show Bold BI text graphic
function show_bold_bi_graphic {
  echo ""
  echo " ██████╗██╗   ██╗██████╗ ███████╗██████╗ ██╗      ██████╗  ██████╗ ██████╗ "
  echo "██╔════╝██║   ██║██╔══██╗██╔════╝██╔══██╗██║     ██╔═══██╗██╔═══██╗██╔══██╗"
  echo "██║     ██║   ██║██████╔╝█████╗  ██████╔╝██║     ██║   ██║██║   ██║██████╔╝"
  echo "██║     ██║   ██║██╔═══╝ ██╔══╝  ██╔══██╗██║     ██║   ██║██║   ██║██╔══██╗"
  echo "╚██████╗╚██████╔╝██║     ███████╗██║  ██║███████╗╚██████╔╝╚██████╔╝██║  ██║"
  echo " ╚═════╝ ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═╝╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝"
  echo ""
}

# Check if S3 bucket details are provided
if [ -n "$aws_access_key" ] && [ -n "$aws_secret_access_key" ] && [ -n "$s3_bucket" ]; then
  # Install s3fs if not present
  install_s3fs

  # Create a new directory
  create_directory $directory

  # Mount S3 bucket
  mount_s3_bucket $directory "$aws_access_key" "$aws_secret_access_key" "$s3_bucket"
else
  say 3 "Skipping S3 bucket mounting details are not provided."
fi

# Install zip if not present
install_zip

# Install k0s
say 4 "Installing k0s..."
if command_exists k0s; then
  say 2 "k0s is already installed."
else
  curl -sSLf https://get.k0s.sh | sudo sh
fi

# Start k0s cluster
say 4 "Starting k0s cluster..."
sudo k0s install controller --single &

sleep 10

sudo k0s start &

# Wait for k0s to start
sleep 10

# Check if k0s cluster is running
if ! k0s kubectl get nodes &> /dev/null; then
  handle_error "k0s cluster is not running."
fi

# Download and unzip Kustomization files from GitHub
repo_url="https://github.com/yourusername/yourrepo/archive/main.zip"
destination="~/private-cloud"
download_and_unzip $repo_url $destination

# Deploy a sample application using Kustomize
say 4 "Deploying Bold BI application..."
kubectl apply -k $destination

# Show Bold BI text graphic
show_bold_bi_graphic

say 2 "Bold BI application deployed successfully!"
