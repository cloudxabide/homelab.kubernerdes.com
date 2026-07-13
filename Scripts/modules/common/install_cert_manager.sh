#!/bin/bash
set -euo pipefail

# modules/common/install_cert_manager.sh — Install cert-manager on the active cluster
#
# Can be run standalone or called from a numbered deployment script.
# When called from another script, KUBECONFIG must already be exported by the
# caller — cert-manager is installed on whichever cluster KUBECONFIG points to.
# When run standalone, set KUBECONFIG before invoking:
#   export KUBECONFIG=~/.kube/rancher   # or whichever cluster
#   Scripts/modules/common/install_cert_manager.sh
#
# Prerequisites:
#   - KUBECONFIG exported and pointing to the target cluster
#   - helm and kubectl available in PATH
#   - env.sh already sourced (or run standalone — this script sources it)
#
# Variables consumed from env.sh:
#   CERTMGR_VERSION      — chart version (e.g. v1.16.3)
#   CERT_MANAGER_SOURCE  — chart reference (repo/chart or OCI URL)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../env.sh
source "${SCRIPT_DIR}/../../env.sh"

if [[ -z "${KUBECONFIG:-}" ]]; then
  echo "ERROR: KUBECONFIG is not set. Export it before calling this module." >&2
  exit 1
fi

echo "==> Installing cert-manager ${CERTMGR_VERSION}..."
helm upgrade --install cert-manager "${CERT_MANAGER_SOURCE}" \
  --namespace cert-manager \
  --create-namespace \
  --version "${CERTMGR_VERSION}" \
  --set crds.enabled=true

kubectl -n cert-manager rollout status deploy/cert-manager --timeout=120s
echo "    cert-manager ${CERTMGR_VERSION} ready."
