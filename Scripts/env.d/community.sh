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
export RKE2_VERSION="v1.34.4+rke2r1"
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
