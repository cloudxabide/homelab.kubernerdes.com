#!/usr/bin/env bash
# env.d/prime.sh — Prime environment variables
#
# Sourced automatically by env.sh when ENVIRONMENT=prime.
# Do not source directly.
#
# Prime = SUSE Prime software pulled from the Prime registry over the internet.
# Requires a valid SUSE Prime subscription and registry credentials stored in
# ~/.config/SUSE/creds (PRIME_USERNAME and PRIME_PASSWORD).

# ---------------------------------------------------------------------------
# Hardware — same 6 NUCs as community, rebuilt into 10.10.15.0/24.
# Node groups, NICs and storage network are defined further down.
# ---------------------------------------------------------------------------
export NUC01_HOST="nuc-01"
export NUC02_HOST="nuc-02"
export NUC03_HOST="nuc-03"

# ---------------------------------------------------------------------------
# Software versions
# ---------------------------------------------------------------------------
export SL_MICRO_VERSION="6.2"
export HARVESTER_VERSION="v1.8.2"   # matches prime.ipxe / config-*-prime-v1.8.2.yaml on nuc-00
export RKE2_VERSION="v1.34.12+rke2r1"
export RANCHER_VERSION="2.13.3"
export CERTMGR_VERSION="v1.19.2"
export NEUVECTOR_CHART_VERSION="2.8.11"
export NEUVECTOR_VERSION="5.4.9"

# ---------------------------------------------------------------------------
# Registry — SUSE Prime registry
# Credentials (PRIME_USERNAME, PRIME_PASSWORD) must be in ~/.config/SUSE/creds
# ---------------------------------------------------------------------------
export PRIME_REGISTRY="registry.rancher.com"
export REGISTRY_MIRROR="${PRIME_REGISTRY}"

PRIME_CREDS_FILE="${HOME}/.config/SUSE/creds"
if [[ -f "${PRIME_CREDS_FILE}" ]]; then
  # shellcheck source=/dev/null
  source "${PRIME_CREDS_FILE}"
else
  echo "WARNING: ${PRIME_CREDS_FILE} not found — Prime registry auth will fail" >&2
fi
unset PRIME_CREDS_FILE

# ---------------------------------------------------------------------------
# Chart and image sources
# ---------------------------------------------------------------------------
export CERT_MANAGER_SOURCE="oci://quay.io/jetstack/charts/cert-manager"
export RANCHER_CHART_REPO="https://charts.rancher.com/server-charts/prime"
export RANCHER_CHART_NAME="rancher-prime/rancher"
export NEUVECTOR_CHART_REPO="https://neuvector.github.io/neuvector-helm/"
export NEUVECTOR_CHART_NAME="neuvector/core"
export OBS_CHART_REPO="https://charts.rancher.com/server-charts/prime/suse-observability"

# ---------------------------------------------------------------------------
# RKE2 install source
# ---------------------------------------------------------------------------
export RKE2_INSTALL_URL="https://get.rke2.io/install-rke2.sh"

# ---------------------------------------------------------------------------
# Harvester node groups + storage network (consumed by 07_post_configure_harvester.sh)
# Same layout as community (one environment runs at a time, so the storage
# VLAN/range can be reused). 6-node cluster: gen10 (NUC10, e1000e onboard, 1Gb USB) are the control-plane
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
# gen10 onboard NIC (eno1, e1000e) hangs under load without this — see Foo/NIC_issue.md
export E1000E_FIX_GENS="gen10"
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

# ---------------------------------------------------------------------------
# TLS — Let's Encrypt wildcard for ${BASE_DOMAIN} via certbot + Route 53 DNS-01
# on nuc-00 (Scripts/nuc-00/harvester_cert_issue.sh). One certificate per
# environment, renewed on nuc-00; the deploy hook updates Harvester and Rancher.
#   HARVESTER_CERT — issued + installed by 07_post_configure_harvester.sh
#   RANCHER_CERT   — installed by 10_install_rancher_manager.sh
#                    (modules/common/rancher_le_cert.sh)
# Leave unset to keep the self-signed certificates (enclave: local CA instead).
# ---------------------------------------------------------------------------
export HARVESTER_CERT="letsencrypt"
export RANCHER_CERT="letsencrypt"
