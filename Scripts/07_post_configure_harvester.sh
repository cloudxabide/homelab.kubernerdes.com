#!/bin/bash
set -euo pipefail

# 07_post_configure_harvester.sh — Post-install Harvester configuration
#
# Prerequisites:
#   - Harvester cluster is up and accessible
#   - KUBECONFIG set to Harvester kubeconfig:
#       export KUBECONFIG=/path/to/harvester-kubeconfig.yaml
#   - Run from nuc-00
#
# What this does:
#   1. Imports .qcow2 VM images discovered from the admin node HTTP server
#   2. Imports cloud-init templates from this repo (served via Apache)
#   3. Enables the rancher-monitoring add-on
#
# For Prime/Enclave: images and templates are served from local Harbor/Hauler
# rather than downloaded from the internet — controlled by REGISTRY_MIRROR and
# IMAGES_BASE_URL derived from env vars.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh"

IMAGES_BASE_URL="http://${ADMIN_IP}/images"
TEMPLATES_BASE_URL="${REPO_BASE}/Files/CloudConfigurationTemplates"

# Sanitize a string into a valid Kubernetes resource name
k8s_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/-\+/-/g' | sed 's/^-//;s/-$//'
}

# ---------------------------------------------------------------------------
# VM Images
# ---------------------------------------------------------------------------
echo "==> Discovering .qcow2 images at ${IMAGES_BASE_URL}/"
IMAGE_FILES=$(curl -fsSL "${IMAGES_BASE_URL}/" \
  | grep -oP '(?<=href=")[^"]+\.qcow2(?=")' | sort -u)

if [[ -z "${IMAGE_FILES}" ]]; then
  echo "    No .qcow2 images found — skipping image import."
  echo "    Place images under /srv/www/htdocs/images/ on nuc-00."
else
  while IFS= read -r filename; do
    basename_file=$(basename "${filename}")
    resource_name=$(k8s_name "${basename_file%.qcow2}")
    image_url="${IMAGES_BASE_URL}/${basename_file}"

    echo "    Importing image: ${basename_file} (resource: ${resource_name})"
    kubectl apply -f - <<EOF
apiVersion: harvesterhci.io/v1beta1
kind: VirtualMachineImage
metadata:
  name: ${resource_name}
  namespace: default
  annotations:
    harvesterhci.io/storageClassName: harvester-longhorn
spec:
  displayName: "${basename_file}"
  sourceType: download
  url: "${image_url}"
EOF
  done <<< "${IMAGE_FILES}"
fi

# ---------------------------------------------------------------------------
# Cloud Configuration Templates
# ---------------------------------------------------------------------------
echo "==> Discovering cloud-init templates at ${TEMPLATES_BASE_URL}/"
TEMPLATE_FILES=$(curl -fsSL "${TEMPLATES_BASE_URL}/" \
  | grep -oP '(?<=href=")[^"]+\.yaml(?=")' | sort -u)

if [[ -z "${TEMPLATE_FILES}" ]]; then
  echo "    No .yaml templates found — skipping cloud config import."
else
  while IFS= read -r filename; do
    basename_file=$(basename "${filename}")
    resource_name=$(k8s_name "${basename_file%.yaml}")
    template_url="${TEMPLATES_BASE_URL}/${basename_file}"

    echo "    Importing template: ${basename_file} (resource: ${resource_name})"
    encoded_content=$(curl -fsSL "${template_url}" | base64 -w 0)

    kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${resource_name}
  namespace: harvester-system
  labels:
    harvesterhci.io/cloud-init-template: "user"
type: Opaque
data:
  cloudInit: ${encoded_content}
EOF
  done <<< "${TEMPLATE_FILES}"
fi

# ---------------------------------------------------------------------------
# Rancher Monitoring add-on
# ---------------------------------------------------------------------------
echo "==> Enabling rancher-monitoring add-on"
kubectl patch addon rancher-monitoring \
  -n cattle-monitoring-system \
  --type merge \
  -p '{"spec":{"enabled":true}}'
echo "    rancher-monitoring enabled — Prometheus/Grafana/Alertmanager deploying"

echo
echo "==> Done. Next step: Scripts/10_install_rancher_manager.sh"
