#!/bin/bash
set -euo pipefail

# modules/common/observability_le_cert.sh — Serve SUSE Observability with the
# environment's Let's Encrypt wildcard certificate. Run on nuc-00.
#
# Called by 21_install_observability.sh when OBS_CERT=letsencrypt, or
# standalone on an existing install:
#   export ENVIRONMENT=prime KUBECONFIG=~/.kube/prime-observability.kubeconfig
#   Scripts/modules/common/observability_le_cert.sh
#
# Reuses the certificate 07_post_configure_harvester.sh issued for Harvester
# (/etc/letsencrypt/live/${BASE_DOMAIN}, covering *.${BASE_DOMAIN}). On
# renewal, certbot's /etc/letsencrypt/renewal-hooks/deploy/cluster-cert-deploy
# (installed here) updates the secret using root's copy of this kubeconfig.
#
# What this does (safe to re-run):
#   1. Gives root a copy of KUBECONFIG and installs the renewal hook
#   2. Writes the certificate into suse-observability/${OBS_TLS_SECRET}
#   3. Points the suse-observability-ui ingress at that secret
#   4. Waits until https://${OBS_HOSTNAME} serves a trusted certificate

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../env.sh
source "${SCRIPT_DIR}/../../env.sh"

: "${KUBECONFIG:?export KUBECONFIG (observability cluster) first}"
LIVE_DIR="/etc/letsencrypt/live/${BASE_DOMAIN}"
ROOT_KUBECONFIG="/root/.kube/${ENVIRONMENT}-observability.kubeconfig"
NAMESPACE="suse-observability"
INGRESS="suse-observability-ui"

if ! sudo test -r "${LIVE_DIR}/fullchain.pem"; then
  echo "ERROR: ${LIVE_DIR} not found — run 07_post_configure_harvester.sh" >&2
  echo "       (HARVESTER_CERT=letsencrypt) first; it issues *.${BASE_DOMAIN}" >&2
  exit 1
fi

echo "==> Observability certificate: Let's Encrypt *.${BASE_DOMAIN}"

# 1. Root's kubeconfig for renewals
sudo install -D -m 600 "${KUBECONFIG}" "${ROOT_KUBECONFIG}"
echo "    root kubeconfig: ${ROOT_KUBECONFIG}"
sudo install -D -m 0755 "${SCRIPT_DIR}/../../nuc-00/cluster-cert-deploy" \
  /etc/letsencrypt/renewal-hooks/deploy/cluster-cert-deploy
echo "    renewal hook: /etc/letsencrypt/renewal-hooks/deploy/cluster-cert-deploy"

# 2. Certificate into the TLS secret
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "${NAMESPACE}" create secret tls "${OBS_TLS_SECRET}" \
  --cert=<(sudo cat "${LIVE_DIR}/fullchain.pem") \
  --key=<(sudo cat "${LIVE_DIR}/privkey.pem") \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Ingress -> secret (21 already sets this; covers existing installs)
if kubectl -n "${NAMESPACE}" get ingress "${INGRESS}" &>/dev/null; then
  kubectl -n "${NAMESPACE}" patch ingress "${INGRESS}" --type merge -p \
    "{\"spec\":{\"tls\":[{\"hosts\":[\"${OBS_HOSTNAME}\"],\"secretName\":\"${OBS_TLS_SECRET}\"}]}}"
else
  echo "    ingress ${INGRESS} not found yet — 21_install_observability.sh creates it"
  exit 0
fi

# 4. Verify with the system trust store. Any HTTP status is fine (the UI may
#    still be starting); only a TLS failure keeps us waiting.
waited=0
until curl -s -o /dev/null "https://${OBS_HOSTNAME}/"; do
  if (( waited >= 300 )); then
    echo "ERROR: https://${OBS_HOSTNAME} still not trusted after 300s" >&2
    exit 1
  fi
  sleep 5; waited=$((waited + 5))
done
echo "    https://${OBS_HOSTNAME} serving a trusted certificate — ok"
