#!/usr/bin/env bash
# env.sh — Central environment configuration for homelab.kubernerdes.com
#
# Source this from any script running on the admin node (nuc-00):
#
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${SCRIPT_DIR}/env.sh"
#
# Override ENVIRONMENT before sourcing to select a different environment:
#
#   ENVIRONMENT=prime source "${SCRIPT_DIR}/env.sh"
#
# Scripts that run on remote nodes (cluster VMs) cannot source this file
# directly — they set ENVIRONMENT/DOMAIN/IP_PREFIX inline at top. See
# install_RKE2.sh for that pattern.
#
# ENVIRONMENTS — all share the 10.10.12.0/22 supernet; each occupies one /24:
#   homelab    — 10.10.12.0/24 — shared infrastructure (DNS, DHCP, admin, NAS)
#   enclave    — 10.10.13.0/24 — nuc-01/02/03 — RGS via Hauler + Harbor (air-gap)
#   community  — 10.10.14.0/24 — nuc-01/02/03 — SUSE/upstream bits, public registries
#   prime      — 10.10.15.0/24 — nuc-01/02/03 — RGS software from RGS registry
# homelab reserves .128-.254 as a dynamic DHCP pool; environment /24s use Harvester DHCP.
#
# NUC01_HOST / NUC02_HOST / NUC03_HOST are set per environment in env.d/.
# All environments use nuc-01 / nuc-02 / nuc-03; distinguished by ENVIRONMENT/domain.

export ENVIRONMENT="${ENVIRONMENT:-community}"
export DOMAIN="kubernerdes.com"
export BASE_DOMAIN="${ENVIRONMENT}.${DOMAIN}"

# ---------------------------------------------------------------------------
# IP addressing
# ---------------------------------------------------------------------------

# Per-environment /24 prefix — all within the 10.10.12.0/22 supernet
case "${ENVIRONMENT}" in
  prime)     export IP_PREFIX="10.10.15" ;;
  enclave)   export IP_PREFIX="10.10.13" ;;
  community) export IP_PREFIX="10.10.14" ;;
  *) echo "ERROR: Unknown ENVIRONMENT '${ENVIRONMENT}'" >&2; return 1 ;;
esac

# ---------------------------------------------------------------------------
# Harvester VM IP helpers
# Fetches all VMIs once at source time; node-IP exports below resolve from
# the cached JSON. Two lookup modes:
#   harvester_vm_ip <name>          — exact name match (rancher-01/02/03)
#   harvester_vm_ips_by_prefix <p>  — prefix match, sorted by name
#                                     (observability-* / apps-* random suffixes)
# Both return empty string (with a stderr warning) when the kubeconfig is
# absent or kubectl is not installed — callers handle empty values naturally
# when they try to SSH/scp to an unresolved host.
# ---------------------------------------------------------------------------
_HARVESTER_KUBECONFIG="${HOME}/.kube/${ENVIRONMENT}-harvester.kubeconfig"
_HARVESTER_VMI_JSON=""
if [[ -f "${_HARVESTER_KUBECONFIG}" ]] && command -v kubectl >/dev/null 2>&1; then
  _HARVESTER_VMI_JSON="$(kubectl --kubeconfig "${_HARVESTER_KUBECONFIG}" \
    get virtualmachineinstances -A -o json 2>/dev/null || true)"
else
  echo "WARN: ${_HARVESTER_KUBECONFIG} not found or kubectl missing — node IPs will be empty" >&2
fi
unset _HARVESTER_KUBECONFIG

harvester_vm_ip() {
  local vm_name="$1"
  [[ -z "${_HARVESTER_VMI_JSON}" ]] && { echo ""; return 0; }
  jq -r --arg n "${vm_name}" \
    '.items[] | select(.metadata.name == $n) | .status.interfaces[0].ipAddress // empty' \
    <<< "${_HARVESTER_VMI_JSON}"
}

harvester_vm_ips_by_prefix() {
  local prefix="$1"
  [[ -z "${_HARVESTER_VMI_JSON}" ]] && { echo ""; return 0; }
  jq -r --arg p "${prefix}" \
    '[.items[] | select(.metadata.name | startswith($p)) | {name: .metadata.name, ip: (.status.interfaces[0].ipAddress // "")}] | sort_by(.name)[] | .ip' \
    <<< "${_HARVESTER_VMI_JSON}"
}

# Supernet constants (fixed — shared by all environments)
export SUPERNET_PREFIX="10.10.12"
export SUBNET_CIDR="${SUPERNET_PREFIX}.0/22"
export SUBNET_MASK="255.255.252.0"
export GATEWAY="${SUPERNET_PREFIX}.1"

# DHCP dynamic pool — homelab /24 only; environment /24s managed by Harvester
export DHCP_RANGE_START="${SUPERNET_PREFIX}.128"
export DHCP_RANGE_END="${SUPERNET_PREFIX}.254"

# ---------------------------------------------------------------------------
# Infrastructure hosts
#
# DNS, DHCP, and TFTP/PXE-HTTP all run on nuc-00 itself — the nuc-00-01
# (DNS primary + DHCP + TFTP) and nuc-00-02 (DNS secondary) infra VMs are
# retired. See Files/nuc-00/ and Scripts/nuc-00/post_install_infra.sh.
# ---------------------------------------------------------------------------
export ADMIN_HOST="nuc-00"
export DNS_HOST="nuc-00"
# nuc-00-03 / LB_HOST is retired but preserved for potential future reuse;
# see Scripts/nuc-00-03/ and Files/nuc-00-03/ for HAProxy config and setup script.
export LB_HOST="nuc-00-03"

# Infrastructure IPs — DNS is shared across all environments (supernet address)
export DNS1_IP="${SUPERNET_PREFIX}.10"
export ADMIN_IP="${IP_PREFIX}.10"
export LB_IP="${IP_PREFIX}.93"  # retired; kept for reference

# Admin web/repo server — repo is cloned to Apache web root and served here
export REPO_BASE="http://${ADMIN_IP}/${BASE_DOMAIN}"

# ---------------------------------------------------------------------------
# Harvester cluster
# ---------------------------------------------------------------------------
export HARVESTER_TOKEN="KentuckyHarvester"
export HARVESTER_PASSWORD="Passw0rd01"
export HARVESTER_VIP="${IP_PREFIX}.100"
export NUC01_IP="${IP_PREFIX}.101"
export NUC02_IP="${IP_PREFIX}.102"
export NUC03_IP="${IP_PREFIX}.103"

# ---------------------------------------------------------------------------
# RKE2 cluster — Rancher Manager
# ---------------------------------------------------------------------------
export RANCHER_VIP="${IP_PREFIX}.30"
export RANCHER_HOSTNAME="rancher.${BASE_DOMAIN}"
export RANCHER_NODE_01="$(harvester_vm_ip "rancher-01")"
export RANCHER_NODE_02="$(harvester_vm_ip "rancher-02")"
export RANCHER_NODE_03="$(harvester_vm_ip "rancher-03")"

# ---------------------------------------------------------------------------
# RKE2 cluster — Observability (provisioned by Rancher Manager)
# ---------------------------------------------------------------------------
export OBS_VIP="${IP_PREFIX}.40"
export OBS_HOSTNAME="observability.${BASE_DOMAIN}"
export OBS_RANCHER_CLUSTER_NAME="${OBS_RANCHER_CLUSTER_NAME:-observability}"
mapfile -t _OBS_IPS < <(harvester_vm_ips_by_prefix "observability-")
export OBS_NODE_01="${_OBS_IPS[0]:-}"
export OBS_NODE_02="${_OBS_IPS[1]:-}"
export OBS_NODE_03="${_OBS_IPS[2]:-}"
unset _OBS_IPS

# ---------------------------------------------------------------------------
# RKE2 cluster — Applications (VM names: apps-<random>)
# ---------------------------------------------------------------------------
export APPS_VIP="${IP_PREFIX}.50"
export APPS_HOSTNAME="apps.${BASE_DOMAIN}"
mapfile -t _APPS_IPS < <(harvester_vm_ips_by_prefix "apps-")
export APPS_NODE_01="${_APPS_IPS[0]:-}"
export APPS_NODE_02="${_APPS_IPS[1]:-}"
export APPS_NODE_03="${_APPS_IPS[2]:-}"
unset _APPS_IPS

# ---------------------------------------------------------------------------
# HAProxy variables (retained for future reuse — nuc-00-03 currently retired)
# These cross-environment node IPs backed the haproxy.cfg template; they use
# the old static-IP scheme and will need updating if HAProxy is reactivated
# with DHCP-assigned nodes.  See Scripts/nuc-00-03/build_haproxy.sh.
# ---------------------------------------------------------------------------
_PRIME_PFX="10.10.15"
_ENCLAVE_PFX="10.10.13"
_COMMUNITY_PFX="10.10.14"

export PRIME_RANCHER_VIP="${_PRIME_PFX}.30"
export PRIME_RANCHER_NODE_01="${_PRIME_PFX}.31"
export PRIME_RANCHER_NODE_02="${_PRIME_PFX}.32"
export PRIME_RANCHER_NODE_03="${_PRIME_PFX}.33"

export PRIME_OBS_VIP="${_PRIME_PFX}.40"
export PRIME_OBS_NODE_01="${_PRIME_PFX}.41"
export PRIME_OBS_NODE_02="${_PRIME_PFX}.42"
export PRIME_OBS_NODE_03="${_PRIME_PFX}.43"

export PRIME_APPS_VIP="${_PRIME_PFX}.50"
export PRIME_APPS_NODE_01="${_PRIME_PFX}.51"
export PRIME_APPS_NODE_02="${_PRIME_PFX}.52"
export PRIME_APPS_NODE_03="${_PRIME_PFX}.53"

export ENCLAVE_RANCHER_VIP="${_ENCLAVE_PFX}.30"
export ENCLAVE_RANCHER_NODE_01="${_ENCLAVE_PFX}.31"
export ENCLAVE_RANCHER_NODE_02="${_ENCLAVE_PFX}.32"
export ENCLAVE_RANCHER_NODE_03="${_ENCLAVE_PFX}.33"

export ENCLAVE_OBS_VIP="${_ENCLAVE_PFX}.40"
export ENCLAVE_OBS_NODE_01="${_ENCLAVE_PFX}.41"
export ENCLAVE_OBS_NODE_02="${_ENCLAVE_PFX}.42"
export ENCLAVE_OBS_NODE_03="${_ENCLAVE_PFX}.43"

export ENCLAVE_APPS_VIP="${_ENCLAVE_PFX}.50"
export ENCLAVE_APPS_NODE_01="${_ENCLAVE_PFX}.51"
export ENCLAVE_APPS_NODE_02="${_ENCLAVE_PFX}.52"
export ENCLAVE_APPS_NODE_03="${_ENCLAVE_PFX}.53"

export COMMUNITY_RANCHER_VIP="${_COMMUNITY_PFX}.30"
export COMMUNITY_RANCHER_NODE_01="${_COMMUNITY_PFX}.31"
export COMMUNITY_RANCHER_NODE_02="${_COMMUNITY_PFX}.32"
export COMMUNITY_RANCHER_NODE_03="${_COMMUNITY_PFX}.33"

export COMMUNITY_OBS_VIP="${_COMMUNITY_PFX}.40"
export COMMUNITY_OBS_NODE_01="${_COMMUNITY_PFX}.41"
export COMMUNITY_OBS_NODE_02="${_COMMUNITY_PFX}.42"
export COMMUNITY_OBS_NODE_03="${_COMMUNITY_PFX}.43"

export COMMUNITY_APPS_VIP="${_COMMUNITY_PFX}.50"
export COMMUNITY_APPS_NODE_01="${_COMMUNITY_PFX}.51"
export COMMUNITY_APPS_NODE_02="${_COMMUNITY_PFX}.52"
export COMMUNITY_APPS_NODE_03="${_COMMUNITY_PFX}.53"

unset _PRIME_PFX _ENCLAVE_PFX _COMMUNITY_PFX

# ---------------------------------------------------------------------------
# Kubeconfig paths (stored on nuc-00)
# ---------------------------------------------------------------------------
export KUBECONFIG_HARVESTER="${HOME}/.kube/${ENVIRONMENT}-harvester.kubeconfig"
export KUBECONFIG_RANCHER="${HOME}/.kube/${ENVIRONMENT}-rancher.kubeconfig"
export KUBECONFIG_OBS="${HOME}/.kube/${ENVIRONMENT}-observability.kubeconfig"
export KUBECONFIG_APPS="${HOME}/.kube/${ENVIRONMENT}-apps.kubeconfig"

# ---------------------------------------------------------------------------
# SSH key used for cluster node access
# ---------------------------------------------------------------------------
export SSH_KEY="${HOME}/.ssh/id_rsa-${ENVIRONMENT}"
export SSH_OPTS="-i ${SSH_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10"

# ---------------------------------------------------------------------------
# Source environment-specific variables
# (registry sources, image versions, credentials, hardware MACs)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.d/community.sh
source "${SCRIPT_DIR}/env.d/${ENVIRONMENT}.sh"
