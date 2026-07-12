#!/usr/bin/env bash
# env.d/enclave.sh — Enclave environment variables
#
# Sourced automatically by env.sh when ENVIRONMENT=enclave.
# Do not source directly.
#
# Enclave = RGS software synced via Hauler, then served from a local Harbor
# registry. Fully air-gapped after initial sync.
#
# Deployment order:
#   1. modules/enclave/hauler_sync.sh  — sync all artifacts (requires internet)
#   2. modules/enclave/harbor_setup.sh — stand up local Harbor registry
#   3. Continue with normal numbered scripts (00_ through 80_)

# ---------------------------------------------------------------------------
# Hardware — nuc-01 / nuc-02 / nuc-03, 10.10.13.0/24
# ---------------------------------------------------------------------------
export NIC_NAME="eno1"
export NUC01_HOST="nuc-01"
export NUC02_HOST="nuc-02"
export NUC03_HOST="nuc-03"
export NUC01_MAC="TODO:enclave-nuc-01-mac"
export NUC02_MAC="TODO:enclave-nuc-02-mac"
export NUC03_MAC="TODO:enclave-nuc-03-mac"

# ---------------------------------------------------------------------------
# Software versions (RGS government-hardened builds)
# ---------------------------------------------------------------------------
export HARVESTER_VERSION="v1.7.1-amd64-govt.1"
export RKE2_VERSION="v1.34.4+rke2r2"
export RANCHER_VERSION="2.13.3"
export CERTMGR_VERSION="v1.19.2"
export NEUVECTOR_CHART_VERSION="2.8.11"
export NEUVECTOR_VERSION="5.4.9"

# ---------------------------------------------------------------------------
# Local Harbor registry (served from admin node or dedicated VM)
# ---------------------------------------------------------------------------
export HARBOR_IP="${IP_PREFIX}.50"
export HARBOR_HOSTNAME="harbor.${BASE_DOMAIN}"
export HARBOR_ADMIN_PASSWORD="ChangeMe-HarborAdmin"
export REGISTRY_MIRROR="${HARBOR_HOSTNAME}"

# ---------------------------------------------------------------------------
# Chart and image sources — all point to local Harbor
# ---------------------------------------------------------------------------
export CERT_MANAGER_SOURCE="oci://${HARBOR_HOSTNAME}/jetstack/charts/cert-manager"
export RANCHER_CHART_REPO="https://${HARBOR_HOSTNAME}/chartrepo/rancher"
export RANCHER_CHART_NAME="rancher/rancher"
export NEUVECTOR_CHART_REPO="https://${HARBOR_HOSTNAME}/chartrepo/neuvector"
export NEUVECTOR_CHART_NAME="neuvector/core"
export OBS_CHART_REPO="https://${HARBOR_HOSTNAME}/chartrepo/suse-observability"

# ---------------------------------------------------------------------------
# Hauler artifact store
# ---------------------------------------------------------------------------
export HAULER_STORE="/opt/hauler"
export HAULER_SERVE_PORT="5000"

# ---------------------------------------------------------------------------
# RKE2 install source — served locally from nuc-00 after Hauler sync
# ---------------------------------------------------------------------------
export RKE2_INSTALL_URL="http://${ADMIN_IP}/rke2/install.sh"
