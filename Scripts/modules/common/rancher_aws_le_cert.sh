#!/bin/bash
set -euo pipefail

# modules/common/rancher_aws_le_cert.sh — Serve the AWS-hosted Rancher with its
# own Let's Encrypt certificate for rancher-aws.${BASE_DOMAIN}. Run on nuc-00.
#
# Called by 10_install_rancher_manager.sh when RANCHER_LOCATION=aws and
# RANCHER_CERT=letsencrypt, or standalone:
#   export ENVIRONMENT=prime RANCHER_LOCATION=aws
#   export KUBECONFIG=~/.kube/prime-rancher-aws.kubeconfig
#   Scripts/modules/common/rancher_aws_le_cert.sh
#   STAGING=1 Scripts/modules/common/rancher_aws_le_cert.sh   # test run
#
# Unlike rancher_le_cert.sh (on-prem), this does NOT use nuc-00's
# *.${BASE_DOMAIN} wildcard: that key stays on nuc-00, and nuc-00's certbot
# lineage and deploy hook are untouched. Instead cert-manager in the AWS
# cluster issues and renews a certificate for the one name itself, solving
# DNS-01 in Route 53 with rancher-01's instance role (OpenTofu/aws/iam.tf,
# rancher_cert_dns01) — no AWS keys in the cluster, renewals need nothing from
# the homelab.
#
# What this does (safe to re-run):
#   1. ClusterIssuer letsencrypt-route53 (or letsencrypt-route53-staging)
#   2. Certificate cattle-system/rancher-aws-tls -> secret tls-rancher-ingress
#   3. Switches the chart to ingress.tls.source=secret, agentTLSMode=system-store
#      (only if it isn't already set that way)
#   4. Clears the cacerts setting left over from Rancher's self-signed CA
#   5. Waits until https://${RANCHER_HOSTNAME} serves a trusted certificate
#
# Needs from the OpenTofu outputs file (AWS_OUTPUTS_FILE): route53_zone_id,
# aws_region. cert-manager must already be installed (10 does that).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../env.sh
source "${SCRIPT_DIR}/../../env.sh"

: "${KUBECONFIG:?export KUBECONFIG (AWS Rancher cluster) first}"
if [[ "${RANCHER_LOCATION}" != "aws" ]]; then
  echo "ERROR: RANCHER_LOCATION=${RANCHER_LOCATION} — this module is for the AWS Rancher;" >&2
  echo "       on-prem uses modules/common/rancher_le_cert.sh" >&2
  exit 1
fi

ZONE_ID="$(aws_output '.route53_zone_id.value')"
REGION="$(aws_output '.aws_region.value')"
if [[ -z "${ZONE_ID}" || -z "${REGION}" ]]; then
  echo "ERROR: route53_zone_id / aws_region missing from ${AWS_OUTPUTS_FILE}" >&2
  echo "       Re-export it: tofu -chdir=OpenTofu/aws output -json > ${AWS_OUTPUTS_FILE}" >&2
  exit 1
fi

if [[ "${STAGING:-0}" == "1" ]]; then
  ISSUER="letsencrypt-route53-staging"
  ACME_SERVER="https://acme-staging-v02.api.letsencrypt.org/directory"
else
  ISSUER="letsencrypt-route53"
  ACME_SERVER="https://acme-v02.api.letsencrypt.org/directory"
fi
CERT_NAME="rancher-aws-tls"
SECRET_NAME="tls-rancher-ingress"

echo "==> Rancher (AWS) certificate: Let's Encrypt ${RANCHER_HOSTNAME} via cert-manager (${ISSUER})"

# 1. ClusterIssuer — DNS-01 in Route 53, ambient credentials (instance role)
EMAIL_LINE=""
[[ -n "${ACME_EMAIL:-}" ]] && EMAIL_LINE="    email: ${ACME_EMAIL}"
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ${ISSUER}
spec:
  acme:
    server: ${ACME_SERVER}
${EMAIL_LINE}
    privateKeySecretRef:
      name: ${ISSUER}-account
    solvers:
    - selector:
        dnsNames:
        - ${RANCHER_HOSTNAME}
      dns01:
        route53:
          region: ${REGION}
          hostedZoneID: ${ZONE_ID}
EOF

# 2. Certificate -> the secret the Rancher chart reads
kubectl create namespace cattle-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${CERT_NAME}
  namespace: cattle-system
spec:
  secretName: ${SECRET_NAME}
  dnsNames:
  - ${RANCHER_HOSTNAME}
  issuerRef:
    kind: ClusterIssuer
    name: ${ISSUER}
EOF

echo "    waiting for cattle-system/${CERT_NAME} (DNS-01 usually takes 1-3 minutes)..."
if ! kubectl -n cattle-system wait certificate/"${CERT_NAME}" --for=condition=Ready --timeout=600s; then
  echo "ERROR: certificate not ready. Look at:" >&2
  echo "  kubectl -n cattle-system describe certificate ${CERT_NAME}" >&2
  echo "  kubectl -n cattle-system get certificaterequest,order,challenge" >&2
  echo "  kubectl -n cert-manager logs deploy/cert-manager | grep -i route53" >&2
  exit 1
fi

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
else
  echo "    chart already uses the secret with agentTLSMode=system-store"
fi

# 4. cacerts: empty means "publicly trusted"
if [[ -n "$(kubectl get settings.management.cattle.io cacerts -o jsonpath='{.value}' 2>/dev/null)" ]]; then
  kubectl patch settings.management.cattle.io cacerts --type merge -p '{"value":""}'
  echo "    cleared cacerts (was Rancher's self-signed CA)"
fi

# 5. Verify with the system trust store (staging certs are not trusted)
if [[ "${STAGING:-0}" == "1" ]]; then
  echo "    STAGING=1: certificate issued from the staging CA (untrusted by design) — re-run without STAGING for a real one"
  exit 0
fi
waited=0
until curl -sf -o /dev/null "https://${RANCHER_HOSTNAME}/ping"; do
  if (( waited >= 300 )); then
    echo "ERROR: https://${RANCHER_HOSTNAME} still not trusted after 300s" >&2
    echo "       Check that ${RANCHER_HOSTNAME} resolves to the Elastic IP from nuc-00 (dig +short)" >&2
    exit 1
  fi
  sleep 5; waited=$((waited + 5))
done
echo "    https://${RANCHER_HOSTNAME} serving a trusted certificate — ok"
