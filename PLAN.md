# PLAN.md


# Conventions, Constraints, Rules, etc...

Credentials NEVER go in this repo.  I will utilize the strategy I have documented [Workstation ENV Management](https://github.com/cloudxabide/devops/blob/main/Workstation_ENV_Management.md).  Essentially, there will be a $HOME/.bashrc.d/(CONCERN) with a matching folder $HOME/.config/(CONCERN) and, if necessary, a matching $HOME/.config/(CONCERN)/creds file that will be sourced by ~/.bashrc.d/creds


# Deployment Steps
## Day 0
- [x] decide on domain and IP scheme (already decided for this project)
- [ ]

## Day 1
- [ ] Build "admin node" (DHCP, DNS, PXE)
- [ ] Retrieve bits (ISO for Harvester and SL-Micro 6.2) and host from admin node
- [ ] Burn ISO to USB stick (alternate: setup PXE on admin node)
- [ ] Install Harvester
  - [ ] Harvester Post-Install (create VMnet, ssh-key, CloudConfigurationFiles, upload Images, create namespaces for each cluster)
- [ ] Install Rancher Manager
  - [ ] Deploy 3-nodes with name prefix: rancher, namespace: vms-rancher
  - [ ] Create IPPool: ippool-rancher=$IP_PREFIX.30
  - [ ] Create Load-Balancer
    - name: lb-rancher
    - backend-server-selector: Key=harvesterhci.io/vmNamePrefix,Value=rancher
    - ports: rancher-http:80,  rancher-https:443, rancher-k8s-api:6443, rancher-rke2:9345
    - health-check: port=6443, period=5s, timeout=3s, success-threshold=1, failure-threshold=3
  - [ ] Install RKE2 on 3 nodes, gather KUBECONFIG
  - [ ] Install Rancher Manager on rancher-manager K8s cluster
- [ ] Add Harvester to Rancher Manager
  - [ ] Enable Harvester Add-On
  - [ ] Add Harvester cluster, retrieve string
  - [ ] Add string to Harvester
- [ ] Install Observability
  - [ ] Create IPPool: ippool-o11y=$IP_PREFIX.40
  - [ ] Create Load-Balancer
    - name: lb-rancher
    - backend-server-selector: Key=guestcluster.harvesterhci.io/name,Value=observability
    - ports: observability-http:80,  observability-https:443, observability-k8s-api:6443, observability-rke2:9345
    - health-check: port=6443, period=5s, timeout=3s, success-threshold=1, failure-threshold=3
  - [ ] Create 3 x VMs using Rancher Manager and Harvester provider
    - cluster name: observability
    - pool name: control-plane
    - machine count: 3
    - CPUs: 8, Memory: 16
    - Image Volume: sl-micro.x86_64-6.2-base-qcow-gm.qcow2
    - Networks | Network: vmnet-vms
    - (Click "Show Advanced") User Data: User Data Template: sl-micro-6.2-generic
- [ ] Install Apps Cluster


## Day 2
- [ ] Configure Backups to utilize TrueNAS
- [ ] Run SUSE Security (NeuVector) demo walkthrough — see [Security_Demo.md](Security_Demo.md)

## Hybrid (AWS) — after the on-prem Day 1 baseline works
Controlled by `RANCHER_LOCATION` / `OBS_LOCATION` = `onprem|aws` (Scripts/env.sh). Hybrid cloud: the AWS-hosted Rancher manages downstream clusters on-prem (Harvester) and in AWS. Not valid for `enclave`. The AWS side is built and torn down on its own and links to on-prem only at connectivity, DNS, and cluster import. Infra code: [OpenTofu/aws](OpenTofu/aws/README.md).
- [ ] Decide connectivity: AWS Site-to-Site VPN vs. Tailscale/WireGuard (VPC `AWS_VPC_CIDR` ↔ 10.10.12.0/22)
- [ ] Decide DNS: Route 53 for `rancher.${BASE_DOMAIN}` vs. nuc-00 forwarding (homelab nodes must resolve it; AWS must resolve Harvester)
- [ ] OpenTofu remote state backend (S3) with OpenTofu state encryption, outside this repo
- [x] OpenTofu: single-AZ VPC, subnets, security groups, 1 x EC2 rancher-01 (SL-Micro 6.2) + Elastic IP, Route 53 record, node-driver IAM user (written, not yet applied)
- [ ] Verify the SL Micro 6.2 AMI lookup + cloud-init support, then first `tofu apply`
- [ ] Tailscale: subnet router in the VPC, nuc-00 advertises 10.10.12.0/22
- [ ] Reuse 09/10 scripts against EC2 nodes (resolve RANCHER_NODE_0x from `tofu output` instead of Harvester VMIs)
- [ ] Let's Encrypt for Rancher in AWS (Route 53 DNS-01 already in use)
- [ ] Integration step (e.g. `Scripts/40_connect_hybrid.sh`): bring up the tunnel, add DNS records, import Harvester + on-prem downstream clusters into the AWS-hosted Rancher
- [ ] Cloud downstream cluster: provision an RKE2 cluster on EC2 from Rancher (Amazon EC2 node driver / cloud credential)
- [ ] Apply SUSE Security + Observability agents to both on-prem and AWS downstream clusters
- [ ] (Optional) Observability in AWS (`OBS_LOCATION=aws`); size EC2 for the SUSE Observability profile
- [ ] Cost estimate + teardown procedure (`tofu destroy`), document in docs site

## Futures/Unknowns
- [ ] CA for Homelab
- [ ] Harbor

