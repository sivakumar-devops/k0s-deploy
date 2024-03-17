# How to Deploy Bold BI for Managed Hosting Requests for Customers

1. Address the customer details in the intranet portal.
   
   [Intranet Portal](https://intranet.syncfusion.com/knowncompany)

3. After obtaining the customer's company name, create a resource group under the customer's company name in the following subscription:
   - Resource group name: `Companyname-kc{KCID}`
     
   [Subscription](https://portal.azure.com/#@syncfusion.com/resource/subscriptions/dc8b2cf7-0d80-4d29-bcba-64a228c5c46e/overview)
   
4. Based on the customer's requirements and plan, choose and create resources with the specific configurations listed below:

| Plan                           | VM Configuration                                       | DB Configuration                              | Blob Size |
|--------------------------------|--------------------------------------------------------|-----------------------------------------------|-----------|
| Small (10 concurrent users)   | 4 vCPU, 16 GB RAM, 256 GB Standard SSD Disk (D4as_v5) | 2 CPU, 8 GB, 128 GB Disk (Standard_D2ads_v5)| 50 GB     |
| Medium (50 concurrent users)  | 8 vCPU, 32 GB RAM, 512 GB Disk (D8as_v5)              | 4 CPU, 16 GB, 256 GB Disk (Standard_D4ads_v5)| 100 GB    |
| Large (100 concurrent users)  | 4 vCPUs, 16 GB RAM, 3 Nodes                            | 4 CPU, 16 GB RAM, 512 GB (Standard_D4ads_v5) | 150 GB    |
| Enterprise (200 concurrent users)| 8 vCPUs, 32 GB RAM, 3 Nodes                          | 8 CPU, 32 GB RAM, 1 TB                        | 200 GB    |

4. Create a VM under the resource group that was created with the customer's name in the following format with specific configuration:
   - VM name: `companyname-kc{KCID}`
   - VM password: random password
   - Configuration: based on the requirement
   - Disk size: based on the requirement
   - Networking: allow ports 80, 443, and 22; enable Delete public IP and NIC when VM is deleted
   - Tag: Environment=production

5. Create a PostgreSQL database as per the requirement with the following configuration:
   - Database server name: `companyname`
   - Password: random password
   - Configuration: based on the requirement
   - Compute type: development
   - Tier: general purpose
   - Disk size: based on the requirement
   - Networking: allow VM IP in inbound rule firewall

6. Create a standard storage account:
   - Storage account name: `companyname`
   - Storage account type: standard
   - Tag: Environment=Customer

7. Create a private endpoint to the VNet of the virtual machine to connect to the NFS storage account below:

   [NFS Storage Account](https://portal.azure.com/#@syncfusion.com/resource/subscriptions/dc8b2cf7-0d80-4d29-bcba-64a228c5c46e/resourceGroups/Shared_Resources/providers/Microsoft.Storage/storageAccounts/nfssharedstorageaccount/overview)
   - Private endpoint name: VM name
   - Private endpoint network: choose the network associated with the VM.
   - Tag: Environment=production

9. Before running the installation command, connect to the VM and perform the following steps:
   1. Copy the SSL certificates to the location `/etc/ssl`.
   2. Map the domain name with the IP address.

10. Run the following command, replacing "company name" with the actual name:

```bash
curl -sSLf https://raw.githubusercontent.com/sivakumar-devops/k0s-deploy/main/deploy.sh | sudo bash -s -- --app_base_url=https://companyname.boldbi.com --folder-name="companyname"

11. Complete the deployment with the azure blob and database server.

12 Enable status page for the site for monitoring.
