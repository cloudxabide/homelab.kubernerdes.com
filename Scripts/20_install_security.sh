#!/bin/bash
set -euo pipefail

# 20_install_security.sh — Deploy SUSE Security (NeuVector) on the apps cluster
#
# Run from nuc-00 with KUBECONFIG pointing to the apps cluster.
#
# Prerequisites:
#   - Apps cluster deployed via Rancher Manager (3-node RKE2 on SL-Micro)
#   - KUBECONFIG saved as ${KUBECONFIG_APPS}
#   - For Prime/Enclave: registry credentials configured
#
# Chart sources are environment-controlled via env.d/:
#   community → neuvector/core from neuvector.github.io
#   prime     → neuvector/core from neuvector.github.io (RGS image override)
#   enclave   → neuvector/core from local Harbor
#
# Reference:
#   https://open-docs.neuvector.com/deploying/kubernetes
#   https://ranchermanager.docs.rancher.com/integrations-in-rancher/neuvector

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh"

export KUBECONFIG="${KUBECONFIG_APPS}"
if ! kubectl get nodes &>/dev/null; then
  echo "ERROR: cannot reach apps cluster via ${KUBECONFIG} — exiting" >&2
  exit 1
fi
echo "==> Apps cluster nodes:"
kubectl get nodes

# ---------------------------------------------------------------------------
# Distro check — this script assumes RKE2 (ingress-nginx, containerd socket
# paths). K3s support is not yet implemented (default Traefik ingress and
# k3s containerd socket paths require separate handling).
# ---------------------------------------------------------------------------
NODE_VERSION="$(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}')"
case "${NODE_VERSION}" in
  *+rke2*) ;;
  *+k3s*)
    echo "ERROR: Detected K3s (kubelet ${NODE_VERSION}) — this script only supports RKE2." >&2
    echo "       K3s is not yet implemented for SUSE Security (see ingress + containerd socket differences)." >&2
    exit 1
    ;;
  *)
    echo "WARNING: Unrecognized Kubernetes distro (kubelet ${NODE_VERSION}) — proceeding, but this script assumes RKE2." >&2
    ;;
esac

# ---------------------------------------------------------------------------
# NeuVector
# ---------------------------------------------------------------------------
echo "==> Adding NeuVector helm repo (${NEUVECTOR_CHART_REPO})..."
helm repo add neuvector "${NEUVECTOR_CHART_REPO}" 2>/dev/null || true
helm repo update

kubectl create namespace cattle-neuvector-system 2>/dev/null || true

echo "==> Installing NeuVector ${NEUVECTOR_VERSION} (chart ${NEUVECTOR_CHART_VERSION})..."
helm upgrade --install neuvector "${NEUVECTOR_CHART_NAME}" \
  --version "${NEUVECTOR_CHART_VERSION}" \
  --namespace cattle-neuvector-system \
  --set manager.svc.type=ClusterIP \
  --set controller.replicas=3 \
  --set cve.scanner.replicas=2 \
  --set controller.pvc.enabled=false \
  --set k3s.enabled=false \
  --set manager.ingress.enabled=false \
  --set global.cattle.url="https://${RANCHER_HOSTNAME}"

kubectl -n cattle-neuvector-system rollout status deploy/neuvector-manager-pod --timeout=300s

# ---------------------------------------------------------------------------
# Ingress for NeuVector Manager UI
# ---------------------------------------------------------------------------
kubectl apply -f - <<EOF
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: neuvector-manager
  namespace: cattle-neuvector-system
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  rules:
    - host: neuvector.${APPS_HOSTNAME}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: neuvector-service-webui
                port:
                  number: 8443
  tls:
    - hosts:
        - neuvector.${APPS_HOSTNAME}
EOF

kubectl get ingress -n cattle-neuvector-system

# ---------------------------------------------------------------------------
# Access info
# ---------------------------------------------------------------------------
BOOTSTRAP=$(kubectl get secret --namespace cattle-neuvector-system neuvector-bootstrap-secret \
  -o go-template='{{ .data.bootstrapPassword|base64decode}}{{ "\n" }}' 2>/dev/null \
  || echo "(not yet available — check after pods are ready)")

echo
echo "========================================"
echo " NeuVector is up!"
echo " URL:      https://neuvector.${APPS_HOSTNAME}"
echo " Password: ${BOOTSTRAP}"
echo "========================================"
echo
echo "Next step: Scripts/21_install_observability.sh"
