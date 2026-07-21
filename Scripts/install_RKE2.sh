#!/bin/bash
set -euo pipefail

# install_RKE2.sh — Install RKE2 on a cluster node
#
# Run as root on each cluster node (rancher-*, observability-*, apps-*).
#   sudo -i bash ~sles/install_RKE2.sh
#
# This script runs on remote nodes and cannot source env.sh directly.
# ENVIRONMENT must be set before running, or defaults to "community".
#
# Node-aware: *-01 is the genesis node; subsequent nodes wait and join.
#
# SL-Micro nodes:
#   After rke2-server starts, this script copies a postboot one-shot to /var
#   (which survives the transactional-update reboot) and reboots.
#   Run install_RKE2_postboot.sh manually after reboot if it did not run.
#
# Install source per environment:
#   community/prime: curl https://get.rke2.io/install-rke2.sh
#   enclave:           curl http://${ADMIN_IP}/rke2/install.sh  (local Hauler)

run_this_script() {
NODES="165 163 164"
for NODE in $NODES; do ssh-keygen -R dhcp-$NODE -f /home/mansible/.ssh/known_hosts; done
for NODE in $NODES; do ssh -o StrictHostKeyChecking=accept-new sles@dhcp-$NODE "uptime"; done
for NODE in $NODES; do scp install_RKE2* dhcp-$NODE:; done
for NODE in $NODES; do ssh -t  dhcp-$NODE "sudo bash -i ./install_RKE2.sh"; done

for NODE in $NODES; do ssh -t  dhcp-$NODE "sudo shutdown now -r"; done
# Grab the kubeconfig from the first node in the list
scp dhcp-${NODES%% *}:.kube/config ~/.kube/community-rancher.kubeconfig
config
}

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: This script must be run as root."
  exit 1
fi

# ---------------------------------------------------------------------------
# Inline environment config (no access to env.sh on remote nodes)
# ---------------------------------------------------------------------------
ENVIRONMENT="${ENVIRONMENT:-community}"
DOMAIN="${DOMAIN:-kubernerdes.com}"
BASE_DOMAIN="${BASE_DOMAIN:-${ENVIRONMENT}.${DOMAIN}}"

case "${ENVIRONMENT}" in
  prime)     IP_PREFIX="10.10.15"; RKE2_INSTALL_URL="https://get.rke2.io/install-rke2.sh";   RKE2_VERSION_DEFAULT="v1.34.7+rke2r1" ;;
  enclave)   IP_PREFIX="10.10.13"; RKE2_INSTALL_URL="http://10.10.12.10/rke2/install.sh"; RKE2_VERSION_DEFAULT="v1.34.7+rke2r1" ;;
  community) IP_PREFIX="10.10.14"; RKE2_INSTALL_URL="https://get.rke2.io/install-rke2.sh";   RKE2_VERSION_DEFAULT="v1.34.7+rke2r1" ;;
  *)
    echo "ERROR: Unknown ENVIRONMENT '${ENVIRONMENT}'"
    exit 1
  ;;
esac

# nuc-00 is a single shared admin host on the homelab supernet — fixed
# address, NOT "${IP_PREFIX}.10" (that octet isn't allocated per-environment;
# see Hardware.md and the ADMIN_IP fix in env.sh).
ADMIN_IP="10.10.12.10"

# ---------------------------------------------------------------------------
# Cluster-specific variables (set based on hostname)
# ---------------------------------------------------------------------------
# Node digit prefix: prime=0, enclave=1, community=2
case "${ENVIRONMENT}" in
  prime)     _NODE_DIG="0" ;;
  enclave)   _NODE_DIG="1" ;;
  community) _NODE_DIG="2" ;;
esac

case $(uname -n) in
  rancher-*)
    cat <<EOF | tee /root/.rke2.vars
export MY_CLUSTER=rancher
export MY_RKE2_VERSION=${RKE2_VERSION:-${RKE2_VERSION_DEFAULT}}
export MY_RKE2_TOKEN=ChangeMe-RancherRKE2
export MY_RKE2_VIP=${IP_PREFIX}.30
export MY_RKE2_HOSTNAME=rancher.${BASE_DOMAIN}
EOF
  ;;
  observability-*)
    cat <<EOF | tee /root/.rke2.vars
export MY_CLUSTER=observability
export MY_RKE2_VERSION=${RKE2_VERSION:-${RKE2_VERSION_DEFAULT}}
export MY_RKE2_TOKEN=ChangeMe-ObsRKE2
export MY_RKE2_VIP=${IP_PREFIX}.40
export MY_RKE2_HOSTNAME=observability.${BASE_DOMAIN}
EOF
  ;;
  apps-*)
    cat <<EOF | tee /root/.rke2.vars
export MY_CLUSTER=apps
export MY_RKE2_VERSION=${RKE2_VERSION:-${RKE2_VERSION_DEFAULT}}
export MY_RKE2_TOKEN=ChangeMe-AppsRKE2
export MY_RKE2_VIP=${IP_PREFIX}.50
export MY_RKE2_HOSTNAME=apps.${BASE_DOMAIN}
EOF
  ;;
  *)
    echo "ERROR: Unrecognised hostname '$(uname -n)'. Add a case block for this cluster."
    exit 1
  ;;
esac

source /root/.rke2.vars

# ---------------------------------------------------------------------------
# Trust the homelab root CA — fetched from the admin node via HTTP.
# Must happen before RKE2 installs so containerd inherits the trust store.
# Published by 02_setup_vault.sh; distributed retroactively by 03_distribute_ca.sh.
# Skipped for community: pulls from public registries, no private CA needed.
# ---------------------------------------------------------------------------
if [[ "${ENVIRONMENT}" != "community" ]]; then
  CA_URL="http://${ADMIN_IP}/homelab-root-ca.crt"
  CA_DEST="/etc/pki/trust/anchors/homelab-root-ca.crt"

  if [[ ! -f "${CA_DEST}" ]]; then
    echo "==> Fetching homelab root CA from ${CA_URL}"
    if curl -fsSL --connect-timeout 10 -o "${CA_DEST}" "${CA_URL}"; then
      update-ca-certificates
      echo "    Root CA trusted."
    else
      echo "    WARNING: Could not fetch CA from ${CA_URL} — continuing without it."
      echo "             Run Scripts/03_distribute_ca.sh from nuc-00 after this node is up."
      rm -f "${CA_DEST}"
    fi
  else
    echo "==> Homelab root CA already trusted."
  fi
fi

# ---------------------------------------------------------------------------
# RKE2 config
# ---------------------------------------------------------------------------
mkdir -p /etc/rancher/rke2

case $(uname -n) in
  *-01)
    cat <<EOF > /etc/rancher/rke2/config.yaml
token: ${MY_RKE2_TOKEN}
tls-san:
  - ${MY_RKE2_VIP}
  - ${MY_RKE2_HOSTNAME}
EOF
  ;;
  *)
    cat <<EOF > /etc/rancher/rke2/config.yaml
server: https://${MY_RKE2_VIP}:9345
token: ${MY_RKE2_TOKEN}
tls-san:
  - ${MY_RKE2_VIP}
  - ${MY_RKE2_HOSTNAME}
EOF
  ;;
esac

# ---------------------------------------------------------------------------
# Install RKE2
# ---------------------------------------------------------------------------
case $(uname -n) in
  *-01) echo "==> Genesis node — installing immediately" ;;
  *)
    SLEEPY_TIME=$(shuf -i 45-90 -n 1)
    echo "==> Worker node — waiting ${SLEEPY_TIME}s before install..."
    sleep "${SLEEPY_TIME}"
  ;;
esac

curl -sfL "${RKE2_INSTALL_URL}" | INSTALL_RKE2_VERSION="${MY_RKE2_VERSION}" sh -

# PATH additions
RKE2_PATH='export PATH=$PATH:/opt/rke2/bin:/var/lib/rancher/rke2/bin'
grep -qxF "${RKE2_PATH}" /root/.bashrc       || echo "${RKE2_PATH}" >> /root/.bashrc
grep -qxF "${RKE2_PATH}" ~sles/.bashrc 2>/dev/null \
  || echo "${RKE2_PATH}" >> ~sles/.bashrc 2>/dev/null || true
export PATH=$PATH:/opt/rke2/bin:/var/lib/rancher/rke2/bin

# ---------------------------------------------------------------------------
# Enable and start RKE2
# ---------------------------------------------------------------------------
case $(uname -n) in
  *-01) echo "==> Starting rke2-server (genesis)" ;;
  *)
    SLEEPY_TIME=$(shuf -i 45-90 -n 1)
    echo "==> Waiting ${SLEEPY_TIME}s for genesis node to be ready..."
    sleep "${SLEEPY_TIME}"
  ;;
esac

systemctl enable rke2-server.service --now

# ---------------------------------------------------------------------------
# Post-install kubeconfig setup
# SL-Micro requires a reboot after transactional update — copy postboot script.
# Other OS: run postboot inline.
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POSTBOOT_SCRIPT="${SCRIPT_DIR}/install_RKE2_postboot.sh"

. /etc/*release* 2>/dev/null || true
case ${NAME:-} in
  SL-Micro)
    echo "==> SL-Micro detected — copying postboot script and rebooting"
    cp "${POSTBOOT_SCRIPT}" /var/lib/install_RKE2_postboot.sh
    chmod 0700 /var/lib/install_RKE2_postboot.sh
    echo "==> After reboot, run: sudo bash /var/lib/install_RKE2_postboot.sh"
    case $(uname -n) in
      *-01) sleep 5 ;;
      *)    sleep $(shuf -i 30-45 -n 1) ;;
    esac
    shutdown -r now
  ;;
  *)
    bash "${POSTBOOT_SCRIPT}"
  ;;
esac
