# CLAUDE.md

# Project Overview
Essentially a lab/demo environment showcasing the capability of SUSE infrastructure and cloud-native software while providing guidance on how to deploy the solution.

There will be a docusaurus repo that tracks this repo providing the guide
https://docs.homelab.kubernerdes.com (https://github.com/cloudxabide/docs.homelab.kubernerdes.com)

- Day 0 - Planning and Architecture  
- Day 1 - Build   
  - Install the following:
  - Harvester 
  - Rancher Manager 
  - Apps cluster (with Security)
  - Observability 
- Day 2 - Operate and Maintain  
  - Backups
  - RBAC

# Architecture & Approach
- Environment will consist of 3 "deployment modes"
  - Community: use software from community projects 
  - Prime: use software from SUSE Prime 
  - Enclave: use software from SUSE Prime and air-gapped tooling 

We will use a variable:ENVIRONMENT={community|prime|enclave} for the "homelab" environment. A separate effort and repo exists for a government-specific, air-gapped deployment; it is not part of this project's community/prime/enclave scheme.
Homelab is a supernet (10.10.12.0/22) and each environment has a /24 (as shown in the next table)

| ENVIRONMENT | CIDR | Purpose |
|:------------|:-----|:--------|
| homelab | 10.10.12.0/22 | Supernet for lab - has "infra services" (DHCP, DNS, PXE, etc...) |
| enclave | 10.10.13.0/24 | Air-gapped deployment using SUSE prime and Hauler |
| community | 10.10.14.0/24 | Deployment using "community bits" |  
| prime  | 10.10.15.0/24 | Deployment using bits from SUSE Prime registry/repo |  
| aws (hybrid) | prime 172.16.0.0/16, community 172.17.0.0/16 (AWS_VPC_CIDR, from reserved 172.16.0.0/12) | VPC for products placed in AWS |

Product placement is a second axis, separate from ENVIRONMENT: `RANCHER_LOCATION` / `OBS_LOCATION` = {onprem|aws} (default onprem). Variable names follow `{PRODUCT}_{ATTRIBUTE}` (e.g. RANCHER_CERT, OBS_VIP). With `aws`, this is a hybrid-cloud setup: the AWS-hosted Rancher manages downstream clusters both on-prem (Harvester) and in AWS. `enclave` must be all on-prem. The AWS side is built and torn down on its own (OpenTofu/aws does not source Scripts/env.sh); it links to on-prem only at connectivity, DNS, and cluster import. The separate "AWS Demo" repo is unrelated to this project. AWS favors cost over resilience: single AZ, single Rancher node (rancher-01, Elastic IP, no load balancer, no NAT by default). Connectivity to on-prem will be Tailscale. The AWS Rancher is `rancher-aws.<env>.kubernerdes.com` (private IP pinned to <vpc>.0.30); `rancher.<env>` always means the on-prem VIP. The AWS Rancher has its own Let's Encrypt cert (cert-manager, Route 53 DNS-01) and its own kubeconfig (`<env>-rancher-aws.kubeconfig`); never point nuc-00's wildcard renewal hook (`/root/.kube/<env>-rancher.kubeconfig`) at it.

# Tech Stack
- SUSE Virtualization (Harvester) 
- SUSE Rancher Manager
- SUSE Security (NeuVector)
- SUSE Observability (StackState)
- SUSE Linux Enterprise (SLE/SLES) / SUSE Linux Enterprise Micro (SL-micro)
- SUSE RKE2 (K3s when needed)
- Hauler
- Harbor 

# Folder Structure
- /Foo :  random directory for test scripts, notes, etc...
- /Images : contains graphical images for repo (architecture overview, branded imagery, etc..)
- /Diagram : network/hardware diagram; update Diagram/inventory.yaml when IPs, hosts, versions or cabling change, then run Diagram/render.sh
- /Scripts : directory to host scripts used to deploy software, typically specific to the "ENVIRONMENT" that is set
- /OpenTofu/aws : AWS infrastructure (OpenTofu, not Terraform) for the hybrid placement (*_LOCATION=aws); no state or creds in repo
- /Files : boilerplate or template with placeholders replaced by "ENVIRONMENT" that is set 

# Coding Conventions
- TBD: not entirely sure what this might entail for the type of project this is
