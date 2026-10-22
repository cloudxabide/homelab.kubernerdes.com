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
#   1. Labels nodes by hardware generation (homelab.kubernerdes.com/nuc-gen)
#      and gives Harvester worker nodes the node-role.kubernetes.io/worker label
#   2. Creates the storage ClusterNetwork + one VlanConfig per hardware gen
#   3. Creates the untagged VM network on the built-in mgmt cluster network
#   4. Creates the 1-replica, best-effort-locality StorageClass
#   5. Applies the storage-network setting (rancher-monitoring is disabled
#      first so no Longhorn volume is attached, as Harvester requires)
#   6. Enables the rancher-monitoring add-on
#   7. Imports .qcow2 VM images discovered from the admin node HTTP server,
#      plus a dedicated copy of the Rancher image on the local StorageClass
#      (after step 5, which restarts Longhorn's backing-image managers)
#   8. Imports cloud-init templates from this repo (served via Apache)
#   9. Installs a Let's Encrypt wildcard certificate for ${BASE_DOMAIN}
#      (HARVESTER_CERT=letsencrypt) — last, because it replaces the
#      self-signed certificate your kubeconfig may still trust
#
# Steps 2-5 are skipped when the environment does not define
# STORAGE_NETWORK_VLAN / VM_NETWORK_NAME / LOCAL_STORAGE_CLASS (see env.d/).
# Safe to re-run: existing objects are left alone, and the storage network
# is only re-applied when its value differs from the desired one.
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

# wait_for <description> <timeout-seconds> <command...>
# Re-runs the command every 5s until it succeeds or the timeout expires.
wait_for() {
  local desc="$1" timeout="$2"; shift 2
  local waited=0
  until "$@" >/dev/null 2>&1; do
    if (( waited >= timeout )); then
      echo "ERROR: timed out after ${timeout}s waiting for: ${desc}" >&2
      return 1
    fi
    sleep 5; waited=$((waited + 5))
  done
  echo "    ${desc} — ok"
}

# ---------------------------------------------------------------------------
# Node labels (hardware generation)
# ---------------------------------------------------------------------------
if [[ -n "${NODE_GENS:-}" ]]; then
  echo "==> Labeling nodes with homelab.kubernerdes.com/nuc-gen"
  for gen in ${NODE_GENS}; do
    nodes_var="NODES_${gen}"
    for node in ${!nodes_var}; do
      if kubectl get node "${node}" >/dev/null 2>&1; then
        kubectl label node "${node}" "homelab.kubernerdes.com/nuc-gen=${gen}" --overwrite >/dev/null
        echo "    ${node} -> ${gen}"
      else
        echo "    WARN: node ${node} not found (not joined yet?) — label it after it joins"
      fi
    done
  done
fi

# ---------------------------------------------------------------------------
# Worker role label
# Nodes installed with "role: worker" get node-role.harvesterhci.io/worker=true
# but no Kubernetes role label, so `kubectl get nodes` shows ROLES <none>.
# ---------------------------------------------------------------------------
echo "==> Labeling Harvester worker nodes with node-role.kubernetes.io/worker"
kubectl label node -l node-role.harvesterhci.io/worker=true \
  node-role.kubernetes.io/worker=true --overwrite

# ---------------------------------------------------------------------------
# Storage ClusterNetwork + per-generation VlanConfigs
# The storage-network setting itself is applied further down, after
# rancher-monitoring has been disabled.
# ---------------------------------------------------------------------------
if [[ -n "${STORAGE_NETWORK_VLAN:-}" ]]; then
  echo "==> Creating ClusterNetwork ${STORAGE_CLUSTER_NETWORK} and VlanConfigs"
  kubectl apply -f - <<EOF
apiVersion: network.harvesterhci.io/v1beta1
kind: ClusterNetwork
metadata:
  name: ${STORAGE_CLUSTER_NETWORK}
EOF

  for gen in ${NODE_GENS}; do
    nic_var="STORAGE_NIC_${gen}"
    # Name pattern strg-<gen> matches the hand-built cluster (strg-gen10/strg-gen13)
    kubectl apply -f - <<EOF
apiVersion: network.harvesterhci.io/v1beta1
kind: VlanConfig
metadata:
  name: strg-${gen}
spec:
  clusterNetwork: ${STORAGE_CLUSTER_NETWORK}
  nodeSelector:
    homelab.kubernerdes.com/nuc-gen: ${gen}
  uplink:
    nics:
      - ${!nic_var}
    bondOptions:
      mode: active-backup
      miimon: -1
    linkAttributes:
      txQLen: -1
EOF
  done

  wait_for "ClusterNetwork ${STORAGE_CLUSTER_NETWORK} ready" 300 \
    sh -c "kubectl get clusternetwork ${STORAGE_CLUSTER_NETWORK} -o jsonpath='{.status.conditions[?(@.type==\"ready\")].status}' | grep -qx True"
fi

# ---------------------------------------------------------------------------
# VM network — untagged, on the built-in mgmt cluster network, so it exists
# on every node regardless of the onboard NIC name (eno1 vs enp86s0)
# ---------------------------------------------------------------------------
if [[ -n "${VM_NETWORK_NAME:-}" ]]; then
  echo "==> Creating VM network ${VM_NETWORK_NAME} (untagged, cluster network mgmt)"
  kubectl apply -f - <<EOF
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: ${VM_NETWORK_NAME}
  namespace: default
  labels:
    network.harvesterhci.io/clusternetwork: mgmt
    network.harvesterhci.io/type: UntaggedNetwork
  annotations:
    network.harvesterhci.io/route: '{"mode":"auto","serverIPAddr":"","cidr":"","gateway":""}'
spec:
  config: '{"cniVersion":"0.3.1","name":"${VM_NETWORK_NAME}","type":"bridge","bridge":"mgmt-br","promiscMode":true,"ipam":{}}'
EOF
fi

# ---------------------------------------------------------------------------
# Local StorageClass — for workloads that replicate their own data (etcd).
# StorageClass parameters are immutable, so only create it when missing.
# ---------------------------------------------------------------------------
if [[ -n "${LOCAL_STORAGE_CLASS:-}" ]]; then
  echo "==> Creating StorageClass ${LOCAL_STORAGE_CLASS} (1 replica, best-effort locality)"
  if kubectl get storageclass "${LOCAL_STORAGE_CLASS}" >/dev/null 2>&1; then
    echo "    already exists — leaving as-is"
  else
    kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${LOCAL_STORAGE_CLASS}
provisioner: driver.longhorn.io
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: Immediate
parameters:
  numberOfReplicas: "1"
  dataLocality: "best-effort"
  staleReplicaTimeout: "30"
  migratable: "true"
  encrypted: "false"
  dataEngine: "v1"
EOF
  fi
fi

# ---------------------------------------------------------------------------
# Storage network setting
# Harvester only applies it while no Longhorn volume is attached, and
# rancher-monitoring (enabled by default on v1.8) holds three. So: disable
# monitoring, wait for every volume to detach, apply, wait for "configured".
# Monitoring is re-enabled in the next section. Any VM that is running also
# keeps its volumes attached — stop all VMs before this step on a cluster
# that already has workloads.
# ---------------------------------------------------------------------------
if [[ -n "${STORAGE_NETWORK_VLAN:-}" ]]; then
  echo "==> Configuring storage-network (VLAN ${STORAGE_NETWORK_VLAN}, ${STORAGE_NETWORK_RANGE})"
  desired=$(jq -cn --argjson vlan "${STORAGE_NETWORK_VLAN}" \
    --arg cn "${STORAGE_CLUSTER_NETWORK}" --arg range "${STORAGE_NETWORK_RANGE}" \
    '{vlan: $vlan, clusterNetwork: $cn, range: $range}')
  current=$(kubectl get settings.harvesterhci.io storage-network -o jsonpath='{.value}')
  current_norm=$( [[ -n "${current}" ]] && jq -c '{vlan, clusterNetwork, range}' <<< "${current}" || echo "" )

  if [[ "${current_norm}" == "${desired}" ]]; then
    echo "    already set to ${desired} — skipping"
  else
    echo "    disabling rancher-monitoring so its volumes detach"
    kubectl patch addon rancher-monitoring -n cattle-monitoring-system \
      --type merge -p '{"spec":{"enabled":false}}'
    wait_for "all Longhorn volumes detached" 600 \
      sh -c "! kubectl -n longhorn-system get volumes.longhorn.io -o jsonpath='{range .items[*]}{.status.state}{\"\\n\"}{end}' | grep -qx attached"

    kubectl patch settings.harvesterhci.io storage-network --type merge \
      -p "$(jq -cn --arg v "${desired}" '{value: $v}')"
    sleep 15   # let the controller reset the previous value's "configured" condition
    wait_for "storage-network configured" 900 \
      sh -c "kubectl get settings.harvesterhci.io storage-network -o json | jq -e '.status.conditions[]? | select(.type==\"configured\" and .status==\"True\" and .reason==\"Completed\")'"
  fi
fi

# ---------------------------------------------------------------------------
# Rancher Monitoring add-on
# ---------------------------------------------------------------------------
echo "==> Enabling rancher-monitoring add-on"
# Harvester rejects any change while an add-on operation is still running
# (e.g. the disable above), so wait for it to settle first.
wait_for "rancher-monitoring add-on idle" 600 \
  sh -c "kubectl -n cattle-monitoring-system get addon rancher-monitoring -o jsonpath='{.status.conditions[?(@.type==\"InProgress\")].status}' | grep -qx False"
if [[ "$(kubectl -n cattle-monitoring-system get addon rancher-monitoring -o jsonpath='{.spec.enabled}')" == "true" ]]; then
  echo "    already enabled"
else
  kubectl patch addon rancher-monitoring \
    -n cattle-monitoring-system \
    --type merge \
    -p '{"spec":{"enabled":true}}'
  echo "    rancher-monitoring enabled — Prometheus/Grafana/Alertmanager deploying"
fi

# ---------------------------------------------------------------------------
# Images and templates come after the storage network: applying it restarts
# Longhorn's backing-image-manager pods, and an image still being imported
# at that moment gets stuck ("Backing image manager pod is not running").
# ---------------------------------------------------------------------------

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
# Rancher Manager image on the local StorageClass
# A VM root disk created from an image uses the image's own lh-<uid>
# StorageClass, built from storageClassParameters below — NOT the target
# class's settings. Without these parameters the Rancher VMs land on 3 remote
# replicas, which is what starved etcd on the previous build.
# Image specs are largely immutable, so only create it when missing.
# ---------------------------------------------------------------------------
if [[ -n "${RANCHER_IMAGE_NAME:-}" && -n "${LOCAL_STORAGE_CLASS:-}" ]]; then
  echo "==> Importing Rancher image ${RANCHER_IMAGE_DISPLAY_NAME} on ${LOCAL_STORAGE_CLASS}"
  if kubectl -n default get virtualmachineimage "${RANCHER_IMAGE_NAME}" >/dev/null 2>&1; then
    echo "    already exists — leaving as-is"
  else
    kubectl apply -f - <<EOF
apiVersion: harvesterhci.io/v1beta1
kind: VirtualMachineImage
metadata:
  name: ${RANCHER_IMAGE_NAME}
  namespace: default
  annotations:
    harvesterhci.io/storageClassName: ${LOCAL_STORAGE_CLASS}
spec:
  displayName: "${RANCHER_IMAGE_DISPLAY_NAME}"
  sourceType: download
  url: "${IMAGES_BASE_URL}/${RANCHER_IMAGE_FILE}"
  targetStorageClassName: ${LOCAL_STORAGE_CLASS}
  storageClassParameters:
    numberOfReplicas: "1"
    dataLocality: "best-effort"
    staleReplicaTimeout: "30"
    migratable: "true"
    encrypted: "false"
EOF
  fi
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
# Let's Encrypt certificate (HARVESTER_CERT=letsencrypt)
# Last on purpose: once Harvester serves the new certificate, a kubeconfig
# with the old self-signed CA embedded stops working.
#
# Needs /root/.aws/credentials on nuc-00 (Route 53 IAM user, see
# Scripts/nuc-00/harvester_cert_issue.sh). Root gets its own copy of
# KUBECONFIG for renewals: server pointed at ${HARVESTER_HOSTNAME} (a
# Let's Encrypt cert can't cover an IP) and no certificate-authority-data,
# so it trusts the system CA store.
#
# Safe to re-run: certbot leaves a valid certificate alone, and the push only
# happens when Harvester isn't already serving the current one (e.g. after
# a rebuild, when nuc-00 still has the certificate).
# ---------------------------------------------------------------------------
if [[ "${HARVESTER_CERT:-}" == "letsencrypt" ]]; then
  echo "==> Let's Encrypt certificate for ${BASE_DOMAIN}"
  ROOT_KUBECONFIG="/root/.kube/${ENVIRONMENT}-harvester.kubeconfig"
  kubectl config view --raw --flatten -o json \
    | jq --arg host "https://${HARVESTER_HOSTNAME}" \
        'del(.clusters[].cluster."certificate-authority-data")
         | .clusters[].cluster.server |= sub("^https://[^/]+"; $host)' \
    | sudo install -D -m 600 /dev/stdin "${ROOT_KUBECONFIG}"
  echo "    root kubeconfig: ${ROOT_KUBECONFIG}"

  # Issues on the first run (and pushes via the deploy hook); no-op after that
  ENVIRONMENT="${ENVIRONMENT}" ACME_EMAIL="${ACME_EMAIL}" "${SCRIPT_DIR}/nuc-00/harvester_cert_issue.sh"

  live="/etc/letsencrypt/live/${BASE_DOMAIN}/fullchain.pem"
  # Root's kubeconfig works whichever certificate Harvester is serving
  served=$(sudo kubectl --kubeconfig "${ROOT_KUBECONFIG}" --insecure-skip-tls-verify \
      get settings.harvesterhci.io ssl-certificates -o jsonpath='{.value}' 2>/dev/null \
    | jq -r '.publicCertificate // empty' 2>/dev/null || true)
  if [[ "${served}" == "$(sudo cat "${live}")" ]]; then
    echo "    Harvester already has the current certificate"
  else
    sudo env INSECURE=1 /usr/local/sbin/harvester-cert-deploy "${BASE_DOMAIN}"
  fi

  wait_for "https://${HARVESTER_HOSTNAME} serving a trusted certificate" 300 \
    curl -sf -o /dev/null "https://${HARVESTER_HOSTNAME}/ping"
  echo "    NOTE: remove certificate-authority-data from your own Harvester"
  echo "          kubeconfig (and use ${HARVESTER_HOSTNAME}, not the VIP IP)."
fi

echo
echo "==> Done. Next step: Scripts/08_create_rancher_vms.sh"
