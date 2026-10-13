#!/usr/bin/env bash
# env.d/community.sh — Community environment variables
#
# Sourced automatically by env.sh when ENVIRONMENT=community.
# Do not source directly.
#
# Community = SUSE/upstream bits pulled from public registries.
# No registry mirror, no credentials required.

# ---------------------------------------------------------------------------
# Hardware — Gen13 NUCs (nuc-01 / nuc-02 / nuc-03), 10.10.14.0/24
# ---------------------------------------------------------------------------
export NIC_NAME="enp86s0"
export NUC01_HOST="nuc-01"
export NUC02_HOST="nuc-02"
export NUC03_HOST="nuc-03"
export NUC01_MAC="48:21:0b:65:ce:e5"
export NUC02_MAC="48:21:0b:65:c2:c7"
export NUC03_MAC="48:21:0b:5d:7a:e6"

# ---------------------------------------------------------------------------
# Software versions
# ---------------------------------------------------------------------------
export HARVESTER_VERSION="v1.7.1"
export RKE2_VERSION="v1.34.12+rke2r1"
export RANCHER_VERSION="2.13.3"
export CERTMGR_VERSION="v1.19.2"
export NEUVECTOR_CHART_VERSION="2.8.11"   # chart for NeuVector 5.4.9
export NEUVECTOR_VERSION="5.4.9"

# ---------------------------------------------------------------------------
# Registry — pull direct from public sources (no mirror)
# ---------------------------------------------------------------------------
export REGISTRY_MIRROR=""

# ---------------------------------------------------------------------------
# Chart and image sources
# ---------------------------------------------------------------------------
export CERT_MANAGER_SOURCE="oci://quay.io/jetstack/charts/cert-manager"
export RANCHER_CHART_REPO="https://releases.rancher.com/server-charts/latest"
export RANCHER_CHART_NAME="rancher-latest/rancher"
export NEUVECTOR_CHART_REPO="https://neuvector.github.io/neuvector-helm/"
export NEUVECTOR_CHART_NAME="neuvector/core"
export OBS_CHART_REPO="https://charts.rancher.com/server-charts/prime/suse-observability"

# ---------------------------------------------------------------------------
# RKE2 install source
# ---------------------------------------------------------------------------
export RKE2_INSTALL_URL="https://get.rke2.io/install-rke2.sh"

# ---------------------------------------------------------------------------
# Harvester node groups + storage network (consumed by 07_post_configure_harvester.sh)
# 6-node cluster: gen10 (NUC10, e1000e onboard, 1Gb USB) are the control-plane
# nodes; gen13 (NUC13, igc onboard, 2.5Gb USB) are workers. Nodes are labeled
# homelab.kubernerdes.com/nuc-gen=<gen>, and each gen gets its own VlanConfig
# because the USB NIC name differs per model. Leave STORAGE_NETWORK_VLAN unset
# in an environment to skip storage-network setup entirely.
# ---------------------------------------------------------------------------
export NODE_GENS="gen10 gen13"
export NODES_gen10="nuc-01 nuc-02 nuc-03"
export NODES_gen13="nuc-04 nuc-05 nuc-06"
export STORAGE_NIC_gen10="enp0s20f0u4"
export STORAGE_NIC_gen13="enp0s13f0u1"
export STORAGE_CLUSTER_NETWORK="storage"
export STORAGE_NETWORK_VLAN="128"
export STORAGE_NETWORK_RANGE="192.168.128.0/24"   # avoids 172.16.0.0/12 (hybrid-cloud headroom)

# ---------------------------------------------------------------------------
# Harvester VM network, storage class, and Rancher Manager VMs
# (consumed by 07_post_configure_harvester.sh and 08_create_rancher_vms.sh)
# ---------------------------------------------------------------------------
export VM_NETWORK_NAME="vmnet-vms"                     # untagged, on the built-in mgmt cluster network
export LOCAL_STORAGE_CLASS="harvester-longhorn-local-1r"  # 1 replica, best-effort locality (strict-local is rejected by Harvester)
export RANCHER_IMAGE_FILE="SL-Micro.x86_64-6.2-Base-qcow-GM.qcow2"
export RANCHER_IMAGE_NAME="sl-micro-x86-64-6-2-local-1r"
export RANCHER_IMAGE_DISPLAY_NAME="sl-micro.x86_64-6.2-local-1r"
export RANCHER_VM_NAMESPACE="vms-rancher"
export RANCHER_VM_PLACEMENT="rancher-01:nuc-01 rancher-02:nuc-02 rancher-03:nuc-03"
export RANCHER_VM_CPU="4"
export RANCHER_VM_MEMORY="8Gi"
export RANCHER_VM_DISK_SIZE="32Gi"
export RANCHER_VM_CLOUDINIT="sl-micro-6-generic.yaml"   # under Files/CloudConfigurationTemplates/
export RANCHER_VM_LABEL_KEY="homelab.kubernerdes.com/app"
export RANCHER_VM_LABEL_VALUE="rancher-manager"
