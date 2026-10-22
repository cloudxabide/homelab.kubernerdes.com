#!/bin/bash
set -euo pipefail

# modules/common/rancher_le_cert.sh — Serve Rancher Manager with the
# environment's Let's Encrypt wildcard certificate. Run on nuc-00.
#
# Called by 10_install_rancher_manager.sh when RANCHER_CERT=letsencrypt, or
# standalone on an existing install:
#   export ENVIRONMENT=prime KUBECONFIG=~/.kube/prime-rancher.kubeconfig
#   Scripts/modules/common/rancher_le_cert.sh
#
# Reuses the certificate 07_post_configure_harvester.sh issued for Harvester
# (/etc/letsencrypt/live/${BASE_DOMAIN}, covering *.${BASE_DOMAIN}), so there
# is one certificate and one renewal per environment. The certbot deploy hook
# (/usr/local/sbin/harvester-cert-deploy) updates Rancher on renewal using
# root's copy of this kubeconfig.
#
# What this does (safe to re-run):
#   1. Gives root a copy of KUBECONFIG for renewals
#   2. Writes the certificate into cattle-system/tls-rancher-ingress
#   3. Switches the chart to ingress.tls.source=secret and
#      agentTLSMode=system-store (agents trust the OS store, not a pinned CA)
#      — only if it isn't already set that way
#   4. Clears the cacerts setting left over from Rancher's self-signed CA
#   5. Waits until https://${RANCHER_HOSTNAME} serves a trusted certificate
#
# Switch before importing downstream clusters (Harvester, apps, ...): agents
# registered against the old self-signed CA would need to be re-registered.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../env.sh
source "${SCRIPT_DIR}/../../env.sh"

: "${KUBECONFIG:?export KUBECONFIG (Rancher cluster) first}"
LIVE_DIR="/etc/letsencrypt/live/${BASE_DOMAIN}"
ROOT_KUBECONFIG="/root/.kube/${ENVIRONMENT}-rancher.kubeconfig"

if ! sudo test -r "${LIVE_DIR}/fullchain.pem"; then
  echo "ERROR: ${LIVE_DIR} not found — run 07_post_configure_harvester.sh" >&2
  echo "       (HARVESTER_CERT=letsencrypt) first; it issues *.${BASE_DOMAIN}" >&2
  exit 1
fi

echo "==> Rancher certificate: Let's Encrypt *.${BASE_DOMAIN}"

# 1. Root's kubeconfig for renewals (the RKE2 API uses its own CA on :6443,
#    so this kubeconfig is unaffected by the ingress certificate)
sudo install -D -m 600 "${KUBECONFIG}" "${ROOT_KUBECONFIG}"
echo "    root kubeconfig: ${ROOT_KUBECONFIG}"

apply_secret() {
  kubectl create namespace cattle-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n cattle-system create secret tls tls-rancher-ingress \
    --cert=<(sudo cat "${LIVE_DIR}/fullchain.pem") \
    --key=<(sudo cat "${LIVE_DIR}/privkey.pem") \
    --dry-run=client -o yaml | kubectl apply -f -
}

# 2. Certificate into the ingress secret
apply_secret

# 3. Chart values
values=$(helm -n cattle-system get values rancher -o json 2>/dev/null || echo '{}')
src=$(jq -r '.ingress.tls.source // "rancher"' <<< "${values}")
mode=$(jq -r '.agentTLSMode // ""' <<< "${values}")
if [[ "${src}" != "secret" || "${mode}" != "system-store" ]]; then
  echo "    switching chart: ingress.tls.source ${src} -> secret, agentTLSMode '${mode}' -> system-store"
  RANCHER_REPO_ALIAS="${RANCHER_CHART_NAME%%/*}"
  helm repo add "${RANCHER_REPO_ALIAS}" "${RANCHER_CHART_REPO}" >/dev/null 2>&1 || true
  helm upgrade rancher "${RANCHER_CHART_NAME}" --version "${RANCHER_VERSION}" \
    -n cattle-system --reuse-values \
    --set ingress.tls.source=secret \
    --set agentTLSMode=system-store
  kubectl -n cattle-system rollout status deploy/rancher --timeout=600s
  # Re-apply in case cert-manager rewrote the secret during the switch
  apply_secret
else
  echo "    chart already uses the secret with agentTLSMode=system-store"
fi

# cert-manager's ingress-shim leaves its Certificate behind when the chart
# drops the issuer annotation. Remove it so it can never overwrite the secret
# (the secret has no owner reference, so it is kept).
kubectl -n cattle-system delete certificate.cert-manager.io tls-rancher-ingress --ignore-not-found

# 4. cacerts: empty means "publicly trusted"; a stale self-signed CA here
#    would make agents pin the wrong certificate.
if [[ -n "$(kubectl get settings.management.cattle.io cacerts -o jsonpath='{.value}')" ]]; then
  kubectl patch settings.management.cattle.io cacerts --type merge -p '{"value":""}'
  echo "    cleared cacerts (was Rancher's self-signed CA)"
fi

# 5. Verify with the system trust store
waited=0
until curl -sf -o /dev/null "https://${RANCHER_HOSTNAME}/ping"; do
  if (( waited >= 300 )); then
    echo "ERROR: https://${RANCHER_HOSTNAME} still not trusted after 300s" >&2
    exit 1
  fi
  sleep 5; waited=$((waited + 5))
done
echo "    https://${RANCHER_HOSTNAME} serving a trusted certificate — ok"
