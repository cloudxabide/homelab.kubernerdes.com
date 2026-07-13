#!/bin/bash
set -euo pipefail

# 21_install_observability.sh — Deploy SUSE Observability
#
# Run from nuc-00 with KUBECONFIG pointing to the observability cluster.
#
# Prerequisites:
#   - Rancher Manager up and the observability cluster provisioned from it
#   - KUBECONFIG_RANCHER at ~/.kube/${ENVIRONMENT}-rancher.kubeconfig
#     (Scripts/10_install_rancher_manager.sh saves this automatically)
#   - O11Y_LICENSE environment variable set (SUSE Observability license key)
#     export O11Y_LICENSE=<your-license-key>
#
# Reference:
#   https://docs.stackstate.com/

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh"

[ -z "${O11Y_LICENSE:-}" ] && { echo "ERROR: O11Y_LICENSE is not set."; exit 1; }

# ---------------------------------------------------------------------------
# Validate Rancher Manager kubeconfig
# Observability is provisioned by Rancher (not imported), so its kubeconfig
# is fetched via the Rancher v3 API — no SSH to obs nodes required.
# ---------------------------------------------------------------------------
if [[ ! -f "${KUBECONFIG_RANCHER}" ]]; then
  echo "ERROR: Rancher kubeconfig not found: ${KUBECONFIG_RANCHER}" >&2
  echo "       Run Scripts/10_install_rancher_manager.sh first." >&2
  exit 1
fi
if ! kubectl --kubeconfig "${KUBECONFIG_RANCHER}" get nodes &>/dev/null; then
  echo "ERROR: Cannot connect to Rancher management cluster using ${KUBECONFIG_RANCHER}" >&2
  echo "       Check that the kubeconfig is valid and the cluster is reachable." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Retrieve kubeconfig via Rancher management cluster CRDs
# KUBECONFIG_RANCHER is the RKE2 admin cert-based kubeconfig (not a Rancher
# UI token), so we use kubectl against the management cluster directly rather
# than the Rancher v3 REST API.
# ---------------------------------------------------------------------------
echo "==> Fetching observability kubeconfig from Rancher Manager (cluster: ${OBS_RANCHER_CLUSTER_NAME})..."

MGMT_CLUSTER_ID=$(kubectl --kubeconfig "${KUBECONFIG_RANCHER}" \
  get clusters.provisioning.cattle.io "${OBS_RANCHER_CLUSTER_NAME}" \
  -n fleet-default \
  -o jsonpath='{.status.clusterName}' 2>/dev/null || true)

if [[ -z "${MGMT_CLUSTER_ID}" ]]; then
  echo "ERROR: Cluster '${OBS_RANCHER_CLUSTER_NAME}' not found in fleet-default namespace" >&2
  echo "       Check OBS_RANCHER_CLUSTER_NAME matches the cluster name in the Rancher UI." >&2
  exit 1
fi

mkdir -p "${HOME}/.kube"
kubectl --kubeconfig "${KUBECONFIG_RANCHER}" \
  get secret -n fleet-default "${OBS_RANCHER_CLUSTER_NAME}-kubeconfig" \
  -o jsonpath='{.data.value}' | base64 -d > "${KUBECONFIG_OBS}"

# The secret's kubeconfig points to Rancher's internal ClusterIP; rewrite
# the server URL to the external hostname so nuc-00 can reach it.
# Also replace certificate-authority-data with insecure-skip-tls-verify
# until a CA is integrated — Rancher's dynamiclistener-ca is self-signed.
sed -i \
  -e "s|server:.*|server: https://${RANCHER_HOSTNAME}/k8s/clusters/${MGMT_CLUSTER_ID}|" \
  -e "s|certificate-authority-data:.*|insecure-skip-tls-verify: true|" \
  "${KUBECONFIG_OBS}"
chmod 664 "${KUBECONFIG_OBS}"

export KUBECONFIG="${KUBECONFIG_OBS}"
echo "==> Observability cluster nodes:"
kubectl get nodes

# ---------------------------------------------------------------------------
# cert-manager (required by Observability)
# ---------------------------------------------------------------------------
"${SCRIPT_DIR}/modules/common/install_cert_manager.sh"

# ---------------------------------------------------------------------------
# SUSE Observability
# ---------------------------------------------------------------------------
echo "==> Adding SUSE Observability helm repo (${OBS_CHART_REPO})..."
helm repo add suse-observability "${OBS_CHART_REPO}" 2>/dev/null || true
helm repo update

WORK_DIR=~/observability-install
mkdir -p "${WORK_DIR}" && cd "${WORK_DIR}"

echo "==> Generating Observability values files..."
export VALUES_DIR="${WORK_DIR}"
helm template \
  --set license="${O11Y_LICENSE}" \
  --set rancherUrl="https://${RANCHER_HOSTNAME}" \
  --set baseUrl="https://${OBS_HOSTNAME}" \
  --set sizing.profile='10-nonha' \
  suse-observability-values \
  suse-observability/suse-observability-values \
  --output-dir "${VALUES_DIR}"

echo "==> Installing SUSE Observability..."
helm upgrade --install suse-observability \
  suse-observability/suse-observability \
  --namespace suse-observability \
  --create-namespace \
  --values "${VALUES_DIR}/suse-observability-values/templates/baseConfig_values.yaml" \
  --values "${VALUES_DIR}/suse-observability-values/templates/sizing_values.yaml" \
  --values "${VALUES_DIR}/suse-observability-values/templates/affinity_values.yaml"

echo "NOTE: Observability takes 15-20 minutes to fully stabilize."

# ---------------------------------------------------------------------------
# Ingress
# ---------------------------------------------------------------------------
kubectl apply -f - <<EOF
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: suse-observability-ui
  namespace: suse-observability
spec:
  ingressClassName: nginx
  rules:
  - host: ${OBS_HOSTNAME}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: suse-observability-router
            port:
              number: 8080
  tls:
  - hosts:
    - ${OBS_HOSTNAME}
EOF

# ---------------------------------------------------------------------------
# Access info
# ---------------------------------------------------------------------------
ADMIN_PASS=$(grep 'admin.*password' \
  "$(find ${VALUES_DIR} -name baseConfig_values.yaml 2>/dev/null | head -1)" \
  2>/dev/null || echo "(check values file in ${WORK_DIR})")

echo
echo "========================================"
echo " SUSE Observability deploying..."
echo " URL:      https://${OBS_HOSTNAME}"
echo " Password: ${ADMIN_PASS}"
echo "========================================"
echo
echo "Next step: Scripts/30_deploy_apps.sh"
