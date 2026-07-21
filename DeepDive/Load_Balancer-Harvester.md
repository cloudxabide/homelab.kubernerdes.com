# Harvester Load Balancer

> [!NOTE] 
> This is simply *one* way of doing this, not *the* way of doing this.

## Narrative
For my "Infra Cluster", I will have 2 machine pools: control-plane, and workers.  The control-plane needs access via ports 6443 (K8s API) and 9345 (RKE2 Services), the workers need port 80 and 443.  (i.e. I don't want to send K8s API traffic to the worker nodes and conversely I don't want to send application traffic to the control-plane nodes.

I create 2 DNS entries:  
infra.kubernerdes.com         IN A 10.10.14.50   # K8s endpoint  
*.apps.infra.kubernerdes.com  IN A 10.10.14.51   # Applications endpoint

## Technical Details

ClusterName: infra
Machine Pools: 
- Pool Name: control-plane, workers

Create DNS records for 
- Kubernetes (K8s) endpoint  
- Application endpoint

IPPool(s)
- infra-k8s
- infra-apps

LoadBalancer(s)
- lb-infra-k8s
- lb-infra-apps

Listeners
- infra-k8s: 6443
- infra-rke2: 9345
- infra-http: 80
- infra-https: 443

| Endpoint                     | IP Addr (range) | IPPool            | Port | Listener Name | Load Balancer Name | 
|:-----------------------------|:----------------|:------------------|:-----|:--------------|:-------------------|
| infra.kubernerdes.com        | 10.10.14.50     | ippool-infra-k8s  | 6443 | infra-k8s     | lb-infra-k8s       |
| infra.kubernerdes.com        | 10.10.14.50     | ippool-infra-k8s  | 9345 | infra-rke2    | lb-infra-k8s       |
| *.apps.infra.kubernerdes.com | 10.10.14.51     | ippool-infra-apps | 80   | infra-http    | lb-infra-apps      |
| *.apps.infra.kubernerdes.com | 10.10.14.51     | ippool-infra-apps | 443  | infra-https   | lb-infra-apps      |

![Harvester Load Balancer Overview](../Images/Harvester_Load_Balancer_Overview.png)

## 
[!NOTE] 
> The following was retrieved using MerlinAI (which I believe used Sonnet for this query)

In Harvester, the Load Balancer's **backend server selector** utilizes standard label selectors consisting of **Key** and **Value** pairs to dynamically identify which Virtual Machines (VMs) should receive incoming network traffic. Rather than hardcoding IP addresses, you assign specific labels to your VMs, and the load balancer automatically targets any VM that matches those exact label configurations. Because Harvester is built on top of Kubernetes, the most commonly used values typically follow standard Kubernetes labeling conventions. 

Administrators generally define these selectors based on the application's architecture, environment, or specific role within the cluster. Because the actual values are user-defined, there is no single "correct" value, but standardizing your naming conventions is a highly recommended best practice for maintainability. 

Here is a table outlining the most commonly used keys and values for backend server selectors:

| Selector Key | Common Values | Purpose |
| :--- | :--- | :--- |
| `app` | `nginx`, `apache`, `grafana` | Identifies the specific application or software stack running on the target VMs. |
| `role` | `backend`, `frontend`, `api` | Defines the specific function of the VM within a distributed system or microservices architecture. |
| `env` or `environment` | `production`, `staging`, `dev` | Ensures the load balancer only routes traffic to VMs within a specific deployment environment. |
| `tier` | `web`, `application`, `db` | Indicates the architectural tier of the server, often used in multi-tier application setups. |

When configuring this in the Harvester UI, you will navigate to the **Backend Server Selector** tab during the Load Balancer creation process. You simply input the exact Key and Value pairs you want to target. If you later deploy a new VM and apply those same matching labels, the Harvester load balancer will automatically detect the new instance and begin routing traffic to it, enabling seamless horizontal scaling. Conversely, if a VM loses that label or goes down, it is removed from the load balancer's target pool.

Ultimately, the most effective backend server selector values are the ones that perfectly align with your organization's internal infrastructure tagging strategy. Using simple, descriptive, and consistent key-value pairs ensures that your network routing remains predictable as your Harvester cluster grows. 


## References


