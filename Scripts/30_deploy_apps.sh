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
# Node targeting — deploy demo workloads to worker nodes if any exist,
# otherwise fall back to scheduling on control-plane nodes (with tolerations).
# ---------------------------------------------------------------------------
WORKER_NODES="$(kubectl get nodes -o json \
  | jq -r '.items[]
      | select(.metadata.labels["node-role.kubernetes.io/control-plane"] == null
          and .metadata.labels["node-role.kubernetes.io/master"] == null)
      | .metadata.name')"

if [[ -n "${WORKER_NODES}" ]]; then
  echo "==> Worker nodes detected — targeting demo workloads at:"
  echo "${WORKER_NODES}" | sed 's/^/      /'

  # Pod-spec fragment for raw manifests (chell-test)
  POD_SPEC_EXTRA="$(cat <<'YAML'
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: node-role.kubernetes.io/control-plane
                    operator: DoesNotExist
                  - key: node-role.kubernetes.io/master
                    operator: DoesNotExist
YAML
)"

  # Equivalent JSON6902 patch op for kustomize-managed manifests (HexGL)
  HEXGL_PATCH_OP="$(cat <<'YAML'
      - op: add
        path: /spec/template/spec/affinity
        value:
          nodeAffinity:
            requiredDuringSchedulingIgnoredDuringExecution:
              nodeSelectorTerms:
                - matchExpressions:
                    - key: node-role.kubernetes.io/control-plane
                      operator: DoesNotExist
                    - key: node-role.kubernetes.io/master
                      operator: DoesNotExist
YAML
)"
else
  echo "==> No dedicated worker nodes found — deploying demo workloads to control-plane nodes"

  POD_SPEC_EXTRA="$(cat <<'YAML'
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          effect: NoSchedule
        - key: node-role.kubernetes.io/etcd
          effect: NoExecute
        - key: node-role.kubernetes.io/master
          effect: NoSchedule
YAML
)"

  HEXGL_PATCH_OP="$(cat <<'YAML'
      - op: add
        path: /spec/template/spec/tolerations
        value:
          - key: node-role.kubernetes.io/control-plane
            effect: NoSchedule
          - key: node-role.kubernetes.io/etcd
            effect: NoExecute
          - key: node-role.kubernetes.io/master
            effect: NoSchedule
YAML
)"
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

  # Discover the base Deployment name so the node-targeting patch below
  # applies regardless of what the upstream chart names it; fall back to
  # "hexgl" (matches the Ingress name/image) if discovery comes up empty.
  HEXGL_DEPLOY_NAME="$(grep -rl '^kind: Deployment$' "$HEXGL_TMP/k8s/base" 2>/dev/null \
    | head -1 | xargs -r grep -m1 '^  name:' | awk '{print $2}')"
  HEXGL_DEPLOY_NAME="${HEXGL_DEPLOY_NAME:-hexgl}"

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
  - target:
      kind: Deployment
      name: ${HEXGL_DEPLOY_NAME}
    patch: |
${HEXGL_PATCH_OP}

images:
  - name: hexgl
    newName: docker.io/cloudxabide/hexgl
    newTag: latest
EOF

  # kustomize silently no-ops a patch whose target name doesn't match any
  # resource (no error, exit 0) — verify the node-targeting patch actually
  # landed before deploying, in case HEXGL_DEPLOY_NAME discovery guessed wrong.
  if ! kubectl kustomize "$HEXGL_TMP/k8s/overlays/${ENVIRONMENT}" | grep -q "node-role.kubernetes.io/control-plane"; then
    echo "ERROR: node-targeting patch did not apply to HexGL Deployment '${HEXGL_DEPLOY_NAME}' (kustomize target name mismatch?) — aborting" >&2
    exit 1
  fi

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

kubectl apply -f - <<EOF
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
${POD_SPEC_EXTRA}
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
