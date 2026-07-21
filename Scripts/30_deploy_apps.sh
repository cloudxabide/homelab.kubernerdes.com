#!/bin/bash
set -euo pipefail

# 30_deploy_apps.sh — Deploy sample workloads to the applications cluster
#
# Run from nuc-00 after the apps cluster is up and NeuVector is deployed.
#
# Deploys:
#   - HexGL: a WebGL racing game (demonstrates app ingress + external access)
#   - chell-test: a network probe pod (demonstrates NeuVector policy enforcement)
#
# These are demo workloads — delete them after demonstrating the platform.
#   kubectl delete namespace hexgl
#   kubectl delete namespace aperture-sci

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh"

export KUBECONFIG="${KUBECONFIG_APPS}"
if ! kubectl get nodes &>/dev/null; then
  echo "ERROR: cannot reach apps cluster via ${KUBECONFIG} — exiting" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# HexGL — futuristic WebGL racing game
# Demonstrates: app ingress, wildcard DNS (*.apps.${BASE_DOMAIN})
# ---------------------------------------------------------------------------
DEPLOY_HEXGL="no"
read -r -t 5 -p "Deploy HexGL demo? [y/N] (5s timeout, default No): " HEXGL_ANSWER || true
echo
case "${HEXGL_ANSWER:-}" in
  y|Y|yes|Yes|YES) DEPLOY_HEXGL="yes" ;;
esac

if [[ "${DEPLOY_HEXGL}" == "yes" ]]; then
  echo "=== Deploying HexGL ==="

  HEXGL_TMP="$(mktemp -d)"
  trap 'rm -rf "$HEXGL_TMP"' EXIT

  git clone --depth=1 https://github.com/jradtke-rgs/HexGL "$HEXGL_TMP"

  mkdir -p "$HEXGL_TMP/k8s/overlays/${ENVIRONMENT}"
  cat > "$HEXGL_TMP/k8s/overlays/${ENVIRONMENT}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: hexgl

resources:
  - ../../base

patches:
  - target:
      kind: Ingress
      name: hexgl
    patch: |
      - op: replace
        path: /spec/rules/0/host
        value: hexgl.${APPS_HOSTNAME}

images:
  - name: hexgl
    newName: docker.io/cloudxabide/hexgl
    newTag: latest
EOF

  bash "$HEXGL_TMP/scripts/deploy.sh" -k "$KUBECONFIG" -o "${ENVIRONMENT}"
  echo "    HexGL deployed: https://hexgl.${APPS_HOSTNAME}"
else
  echo "=== Skipping HexGL deployment ==="
fi

# ---------------------------------------------------------------------------
# chell-test — periodic network probe
# Demonstrates: NeuVector process and network policy enforcement
# ---------------------------------------------------------------------------
echo
echo "=== Deploying chell-test ==="

kubectl apply -f - <<'EOF'
---
apiVersion: v1
kind: Namespace
metadata:
  name: aperture-sci
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: chell-test
  namespace: aperture-sci
  labels:
    app: chell-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: chell-test
  template:
    metadata:
      labels:
        app: chell-test
    spec:
      containers:
        - name: chell-test
          image: nicolaka/netshoot
          command: ["/bin/sh", "-c"]
          args:
            - |
              while true; do
                curl -svo /dev/null https://www.fastly.com 2>&1 | grep subjectAltName
                sleep 5
              done
EOF

echo "    chell-test deployed to namespace aperture-sci"
echo
echo "========================================"
echo " Sample workloads deployed!"
if [[ "${DEPLOY_HEXGL}" == "yes" ]]; then
  echo " HexGL:      https://hexgl.${APPS_HOSTNAME}"
fi
echo " NeuVector:  https://neuvector.${APPS_HOSTNAME}"
echo
echo " To clean up:"
if [[ "${DEPLOY_HEXGL}" == "yes" ]]; then
  echo "   kubectl delete namespace hexgl"
fi
echo "   kubectl delete namespace aperture-sci"
echo "========================================"
echo
echo "Next step: Scripts/80_compare_images.sh (community vs Carbide demo)"
