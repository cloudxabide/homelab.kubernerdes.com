#!/bin/bash
set -euo pipefail

# 10_install_rancher_manager.sh — Deploy cert-manager + Rancher Manager Server
#
# Run from nuc-00 after RKE2 is up on all 3 rancher nodes.
#
# Prerequisites:
#   - RKE2 installed on rancher-01/02/03 (Scripts/install_RKE2.sh)
#   - kubectl and helm available on nuc-00
#   - SSH access to rancher-01 via sles@rancher-01
#   - For Prime/Enclave: run the appropriate module first
#       Prime:   Scripts/modules/prime/registry_auth.sh
#       Enclave: Scripts/modules/enclave/harbor_setup.sh
#
# Chart sources are environment-controlled via env.d/:
#   community → rancher-latest (releases.rancher.com)
#   prime     → rancher-prime  (charts.rancher.com)
#   enclave   → local Harbor
#
# Reference:
#   https://ranchermanager.docs.rancher.com/getting-started/quick-start-guides/deploy-rancher-manager/helm-cli

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh"

# ---------------------------------------------------------------------------
# Validate harvester kubeconfig and resolved rancher-01 IP
# env.sh queries Harvester via kubectl to set RANCHER_NODE_01; without the
# kubeconfig that lookup returns empty and all subsequent SSH/scp calls fail.
# ---------------------------------------------------------------------------
if [[ ! -f "${KUBECONFIG_HARVESTER}" ]]; then
  echo "ERROR: Harvester kubeconfig not found: ${KUBECONFIG_HARVESTER}" >&2
  echo "       Create it first, then re-run this script." >&2
  exit 1
fi
if ! kubectl --kubeconfig "${KUBECONFIG_HARVESTER}" get virtualmachineinstances -A -o name &>/dev/null; then
  echo "ERROR: Cannot connect to Harvester using ${KUBECONFIG_HARVESTER}" >&2
  echo "       Check that the kubeconfig is valid and the cluster is reachable." >&2
  exit 1
fi
if [[ -z "${RANCHER_NODE_01:-}" ]]; then
  echo "ERROR: VM 'rancher-01' not found or has no IP assigned in Harvester" >&2
  exit 1
fi

KUBECONFIG_PATH="${KUBECONFIG_RANCHER}"

# ---------------------------------------------------------------------------
# Retrieve kubeconfig from rancher-01
# ---------------------------------------------------------------------------
echo "==> Fetching kubeconfig from rancher-01 (${RANCHER_NODE_01})..."
mkdir -p "${HOME}/.kube"
scp ${SSH_OPTS} sles@${RANCHER_NODE_01}:.kube/config "${KUBECONFIG_PATH}"
sed -i -e "s/127.0.0.1/${RANCHER_VIP}/g" "${KUBECONFIG_PATH}"
chmod 664 "${KUBECONFIG_PATH}"
export KUBECONFIG="${KUBECONFIG_PATH}"

echo "==> Cluster nodes:"
kubectl get nodes

# ---------------------------------------------------------------------------
# cert-manager
# ---------------------------------------------------------------------------
"${SCRIPT_DIR}/modules/common/install_cert_manager.sh"

# ---------------------------------------------------------------------------
# Vault ClusterIssuer for cert-manager
#
# Creates a dedicated Vault policy + long-lived token so cert-manager can
# request certificates from Vault's PKI engine without using the root token.
# Token TTL is 10 years — rotate when rebuilding Vault.
# Requires: 02_setup_vault.sh completed on nuc-00; vault CLI in PATH.
# ---------------------------------------------------------------------------
VAULT_ADDR="${VAULT_ADDR:-http://${ADMIN_IP}:8200}"
VAULT_INIT_FILE="${VAULT_INIT_FILE:-/root/vault-init.json}"

if command -v vault >/dev/null 2>&1 && [[ -f "${VAULT_INIT_FILE}" ]]; then
  echo "==> Configuring cert-manager Vault ClusterIssuer"
  export VAULT_ADDR
  export VAULT_TOKEN
  VAULT_TOKEN=$(jq -r '.root_token' "${VAULT_INIT_FILE}")

  vault policy write cert-manager - << 'POLICY'
path "pki/sign/homelab-server" { capabilities = ["update"] }
path "pki/sign/homelab-client" { capabilities = ["update"] }
POLICY

  CERTMGR_TOKEN=$(vault token create \
    -policy=cert-manager \
    -ttl=87600h \
    -renewable=false \
    -display-name="cert-manager-${ENVIRONMENT}" \
    -format=json | jq -r '.auth.client_token')

  kubectl create secret generic cert-manager-vault-token \
    --namespace cert-manager \
    --from-literal=token="${CERTMGR_TOKEN}" \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl apply -f - << EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: vault-homelab
spec:
  vault:
    server: ${VAULT_ADDR}
    path: pki/sign/homelab-server
    auth:
      tokenSecretRef:
        name: cert-manager-vault-token
        key: token
EOF

  echo "    ClusterIssuer 'vault-homelab' ready."
  echo "    Token expires in 10 years — rotate with 10_install_rancher_manager.sh when rebuilding Vault."
else
  echo "    INFO: Vault not found or ${VAULT_INIT_FILE} missing — skipping ClusterIssuer."
  echo "         Run 02_setup_vault.sh on nuc-00, then re-run this script."
fi

# ---------------------------------------------------------------------------
# Rancher Manager
# ---------------------------------------------------------------------------
echo "==> Adding Rancher helm repo (${RANCHER_CHART_REPO})..."
RANCHER_REPO_ALIAS="${RANCHER_CHART_NAME%%/*}"
helm repo add "${RANCHER_REPO_ALIAS}" "${RANCHER_CHART_REPO}" 2>/dev/null || true
helm repo update

echo "==> Installing Rancher ${RANCHER_VERSION}..."
RANCHER_EXTRA_ARGS=()
case "${ENVIRONMENT}" in
  prime)
    # Use the RGS registry as the default for all Rancher-deployed images
    RANCHER_EXTRA_ARGS+=(--set "systemDefaultRegistry=${RGS_REGISTRY}")
  ;;
  enclave)
    # RGS_REGISTRY is only defined for prime — enclave mirrors through its
    # own local Harbor instead (RGS_REGISTRY would be unbound here).
    RANCHER_EXTRA_ARGS+=(--set "systemDefaultRegistry=${HARBOR_HOSTNAME}")
  ;;
esac

helm upgrade --install rancher "${RANCHER_CHART_NAME}" \
  --version "${RANCHER_VERSION}" \
  --namespace cattle-system \
  --create-namespace \
  --set hostname="${RANCHER_HOSTNAME}" \
  --set replicas=3 \
  --set bootstrapPassword=ChangeMe-RancherBootstrap \
  "${RANCHER_EXTRA_ARGS[@]}"

kubectl -n cattle-system rollout status deploy/rancher --timeout=300s

# ---------------------------------------------------------------------------
# Print access info
# ---------------------------------------------------------------------------
BOOTSTRAP_PASSWORD=$(kubectl get secret --namespace cattle-system bootstrap-secret \
  -o go-template='{{.data.bootstrapPassword|base64decode}}{{ "\n" }}' 2>/dev/null \
  || echo "ChangeMe-RancherBootstrap")

echo
echo "========================================"
echo " Rancher Manager is up!"
echo " URL:      https://${RANCHER_HOSTNAME}/dashboard/?setup=${BOOTSTRAP_PASSWORD}"
echo " Password: ${BOOTSTRAP_PASSWORD}"
echo "========================================"
echo
echo "Next step: Scripts/20_install_security.sh"
