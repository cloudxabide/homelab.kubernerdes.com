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

We will use a variable:ENVIRONMENT={community|prime|enclave} for the "homelab" environment. "carbide-enclave" is a separate effort and repo for using RGS bits in an air-gapped deployment.
Homelab is a supernet (10.10.12.0/22) and each environment has a /24 (as shown in the next table)

| ENVIRONMENT | CIDR | Purpose |
|:------------|:-----|:--------|
| homelab | 10.10.12.0/22 | Supernet for lab - has "infra services" (DHCP, DNS, PXE, etc...) |
| enclave | 10.10.13.0/24 | Air-gapped deployment using SUSE prime and Hauler |
| community | 10.10.14.0/24 | Deployment using "community bits" |  
| prime  | 10.10.15.0/24 | Deployment using bits from SUSE Prime registry/repo |  

# Tech Stack
- SUSE Virtualization (Harvester) 
- SUSE Rancher Manager
- SUSE Security (NeuVector)
- SUSE Observability (StackState)
- SUSE Linux Enterprise (SLE/SLES) / SUSE Linux Enterprise Micro (SL-micro)
- SUSE RKE2 (K3s when needed)
- RGS Hauler
- Harbor 

# Folder Structure
- /Foo :  random directory for test scripts, notes, etc...
- /Images : contains graphical images for repo (architecture overview, branded imagery, etc..)
- /Scripts : directory to host scripts used to deploy software, typically specific to the "ENVIRONMENT" that is set
- /Files : boilerplate or template with placeholders replaced by "ENVIRONMENT" that is set 

# Coding Conventions
- TBD: not entirely sure what this might entail for the type of project this is
