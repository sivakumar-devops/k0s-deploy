# How to Deploy Bold BI in k0s Cluster with Redis and Nginx

The following steps guide you through the automated deployment of Bold BI with Redis and Nginx servers.

## Prerequisites:
- Linux VM with 4 vCPU and 16 GB RAM (Ubuntu 20.04 or kernel v3.10 or newer).
- Managed Database server: PostgreSQL (pgsql), MySQL, or Microsoft SQL Server (mssql).

## Installation Steps:
Execute the following command to install Bold BI with Redis and Nginx. After the installation is completed, you can access Bold BI on your machine's IP with port number 30080, and Redis on port 32379.

```bash
curl -sSLf https://raw.githubusercontent.com/sivakumar-devops/k0s-deploy/main/deploy.sh | sudo bash
