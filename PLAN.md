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
    - health-check: TBD
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
    - health-check: TBD
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

## Futures/Unknowns
- [ ] CA for Homelab
- [ ] Harbor

