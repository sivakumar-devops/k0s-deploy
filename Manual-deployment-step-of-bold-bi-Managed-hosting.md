# How to Manage Site Hosting for Bold BI

When it comes to hosting Bold BI, the deployment strategy depends on pricing tiers and the number of concurrent users. We offer two hosting options: 
single k0s node and multi k8s node deployment. Refer to the following for detailed deployment steps:

1. [Hosting on Single k0s Node](#hosting-on-single-k0s-node)

2. [Hosting on Multi k8s Node](#hosting-on-multi-k8s-node)

## Hosting on Single k0s Node

### Overview

For hosting on a single k0s node, the deployment is tailored based on the number of concurrent users. Please find the required resource details in the table below and follow the steps outlined:

| Plan                       | VM Configuration                                        | DB Configuration                             | Blob Size |
|----------------------------|---------------------------------------------------------|----------------------------------------------|-----------|
| Small (10 concurrent users) | 4 vCPU, 16 GB RAM, 256 GB Standard SSD Disk (D4as_v5)   | 2 CPU, 8 GB, 128 GB Disk (Standard_D2ads_v5) | 50 GB      |
| Medium (50 concurrent users)| 8 vCPU, 32 GB RAM, 512 GB Disk (D8as_v5)                | 4 CPU, 16 GB, 256 GB Disk (Standard_D4ads_v5)| 100 GB     |

### Steps for Hosting Bold BI on a Single k0s Node Cluster

**Step 1:** Create an Azure VM based on your plan and the number of users.

**Step 2:** Set up a PostgreSQL DB server based on your selected plan.

**Step 3:** Create a standard storage account for Blob container storage.

**Step 4:** Add a private endpoint for the shared NFS file share to connect with the VM.

**Step 5:** Connect to the VM and run the following command, replacing the placeholders with your desired values for the application URL and folder name for app data storage:

```bash
curl -sSLf https://raw.githubusercontent.com/sivakumar-devops/k0s-deploy/main/deploy.sh | sudo bash -s -- --app_base_url=http://localhost --folder-name="CustomerKCID/Name"
```

## Hosting on Multi k8s Node

### Overview

For hosting on a multi k8s nodes, the deployment is tailored based on the number of concurrent users. Please find the required resource details in the table below and follow the steps outlined:

| Plan                           | Node Configuration                     | DB Configuration                               | Blob Size |
|--------------------------------|-----------------------------------------|------------------------------------------------|-----------|
| Large (100 concurrent users)    | 4 vCPUs, 16 GB RAM, 3 Node              | 4 CPU, 16 GB RAM, 512 GB (Standard_D4ads_v5)   | 150 GB    |
| Enterprise (200 concurrent users)| 8 vCPUs, 32 GB RAM, 3 Node              | 8 CPU, 32 GB RAM, 1 TB                          | 200 GB    |


Feel free to adapt these steps based on your specific requirements and configurations.



