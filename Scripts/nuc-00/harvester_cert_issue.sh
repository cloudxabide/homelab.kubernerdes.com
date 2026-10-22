#!/bin/bash
set -euo pipefail

# harvester_cert_issue.sh — Issue a Let's Encrypt wildcard certificate for an
# environment and install it in Harvester. Run on nuc-00.
#
#   ENVIRONMENT=prime Scripts/nuc-00/harvester_cert_issue.sh
#   ENVIRONMENT=prime STAGING=1 Scripts/nuc-00/harvester_cert_issue.sh   # test run
#
# What this does:
#   1. Installs certbot + the Route 53 DNS plugin and enables the renewal timer
#   2. Installs harvester-cert-deploy to /usr/local/sbin (the deploy hook)
#   3. Requests ${BASE_DOMAIN} + *.${BASE_DOMAIN} with a DNS-01 challenge in
#      Route 53 (Harvester's VIP is private, so HTTP-01 can't work)
#   4. certbot runs the deploy hook, which patches Harvester's
#      ssl-certificates setting. Renewals rerun the same hook automatically.
#
# Prerequisites (on nuc-00):
#   - /root/.aws/credentials with an IAM user that can change records in the
#     kubernerdes.com hosted zone (route53:ListHostedZones, GetChange,
#     ChangeResourceRecordSets)
#   - /root/.kube/${ENVIRONMENT}-harvester.kubeconfig pointing at
#     https://harvester.${BASE_DOMAIN}, with no certificate-authority-data
#
# Optional:
#   ACME_EMAIL — Let's Encrypt account email for expiry notices (none by default)
#   STAGING=1  — use the Let's Encrypt staging CA (untrusted certs, generous rate limits)
#
# The first push happens while Harvester still serves its self-signed
# certificate, so it runs with INSECURE=1. Later renewals verify TLS normally.
#
# Enclave: issuing only needs nuc-00 to reach Let's Encrypt and Route 53,
# not Harvester. Whether an air-gapped enclave should use a public cert or an
# internal CA is still an open decision.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVIRONMENT="${ENVIRONMENT:-community}"
BASE_DOMAIN="${ENVIRONMENT}.kubernerdes.com"
HOOK="/usr/local/sbin/harvester-cert-deploy"

echo "==> Installing certbot and the Route 53 plugin"
sudo zypper --non-interactive install --no-recommends \
  python3-certbot python3-certbot-dns-route53 certbot-systemd-timer >/dev/null
sudo systemctl enable --now certbot-renew.timer 2>/dev/null \
  || echo "    WARN: certbot-renew.timer not found — check: systemctl list-timers | grep certbot"

echo "==> Installing deploy hook ${HOOK}"
sudo install -m 0755 "${SCRIPT_DIR}/harvester-cert-deploy" "${HOOK}"

for f in /root/.aws/credentials "/root/.kube/${ENVIRONMENT}-harvester.kubeconfig"; do
  sudo test -r "${f}" || { echo "ERROR: ${f} missing — see Prerequisites" >&2; exit 1; }
done

CERTBOT_ARGS=(certonly --non-interactive --agree-tos
  --dns-route53
  --cert-name "${BASE_DOMAIN}"
  -d "${BASE_DOMAIN}" -d "*.${BASE_DOMAIN}"
  --deploy-hook "${HOOK}")
if [[ -n "${ACME_EMAIL:-}" ]]; then
  CERTBOT_ARGS+=(--email "${ACME_EMAIL}")
else
  CERTBOT_ARGS+=(--register-unsafely-without-email)
fi
if [[ "${STAGING:-0}" == "1" ]]; then
  # --break-my-certs lets a staging cert replace a production one (and back)
  CERTBOT_ARGS+=(--staging --break-my-certs --force-renewal)
fi

echo "==> Requesting ${BASE_DOMAIN} + *.${BASE_DOMAIN}${STAGING:+ (staging)}"
# The hook runs inside certbot. INSECURE=1 covers the first push, while
# Harvester still serves its self-signed certificate.
sudo env INSECURE=1 certbot "${CERTBOT_ARGS[@]}"

echo
echo "==> Done. Check from any machine:"
echo "    curl -sv https://harvester.${BASE_DOMAIN} -o /dev/null 2>&1 | grep -E 'subject|issuer|verify'"
