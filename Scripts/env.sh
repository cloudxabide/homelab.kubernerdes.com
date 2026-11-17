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
#   enclave    — 10.10.13.0/24 — nuc-01/02/03 — Prime software via Hauler + Harbor (air-gap)
#   community  — 10.10.14.0/24 — nuc-01/02/03 — SUSE/upstream bits, public registries
#   prime      — 10.10.15.0/24 — nuc-01/02/03 — SUSE Prime software from the Prime registry
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
# Product placement — where each management-plane product runs.
#   onprem — Harvester VMs on the NUCs (default; the original design)
#   aws    — EC2 in AWS (hybrid); infra lives under OpenTofu/aws/
# Hybrid cloud: a Rancher in AWS manages downstream clusters on-prem (Harvester)
# and in AWS (EC2, provisioned by Rancher).
# enclave is air-gapped, so it must stay fully on-prem.
#
#   RANCHER_LOCATION=aws ./10_install_rancher_manager.sh
# ---------------------------------------------------------------------------
export RANCHER_LOCATION="${RANCHER_LOCATION:-onprem}"
export OBS_LOCATION="${OBS_LOCATION:-onprem}"
for _loc_var in RANCHER_LOCATION OBS_LOCATION; do
  case "${!_loc_var}" in
    onprem|aws) ;;
    *) echo "ERROR: ${_loc_var}='${!_loc_var}' — must be onprem or aws" >&2; unset _loc_var; return 1 ;;
  esac
  if [[ "${ENVIRONMENT}" == "enclave" && "${!_loc_var}" != "onprem" ]]; then
    echo "ERROR: ${_loc_var}=${!_loc_var} is not valid for ENVIRONMENT=enclave (air-gapped)" >&2
    unset _loc_var; return 1
  fi
done
unset _loc_var

# AWS side of the hybrid setup (only used when a *_LOCATION=aws).
# The VPC comes from 172.16.0.0/12, which is kept clear of the
# homelab (10.10.12.0/22) and the Harvester storage network (192.168.128.0/24).
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_VPC_CIDR="${AWS_VPC_CIDR:-172.16.0.0/16}"

# ---------------------------------------------------------------------------
# ENVIRONMENT sanity check — a reminder in case the wrong one is set.
# Waits 5 seconds: N aborts, Y/Enter/timeout proceeds.
# Skipped when:
#   - env.sh is sourced from an interactive prompt (not from a script)
#   - there is no terminal (piped / cron / CI)
#   - it already ran (modules re-source env.sh; the flag is exported)
#   - ENV_CONFIRMED=1 is set by the caller (e.g. ENV_CONFIRMED=1 ./07_...sh)
# ---------------------------------------------------------------------------
if [[ ${#BASH_SOURCE[@]} -gt 1 && -t 0 && "${ENV_CONFIRMED:-0}" != "1" ]]; then
  echo "ENVIRONMENT is currently set to: ${ENVIRONMENT}  (${IP_PREFIX}.0/24, ${BASE_DOMAIN})"
  echo "  RANCHER_LOCATION=${RANCHER_LOCATION}  OBS_LOCATION=${OBS_LOCATION}"
  _env_answer=""
  read -r -t 5 -p "Is ENVIRONMENT=${ENVIRONMENT} what you want (Y/N)? " _env_answer || echo
  case "${_env_answer}" in
    [Nn]*) echo "Aborting. Set it with: export ENVIRONMENT={community|prime|enclave}" >&2; exit 1 ;;
  esac
  unset _env_answer
  export ENV_CONFIRMED=1
fi

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
#
# The Harvester kubeconfig carries two contexts: "rancher" (the management
# API, server URL with no cluster path) and "local" (the Harvester cluster's
# own API, proxied at /k8s/clusters/local) — VMIs are a kubevirt CRD that
# only exists under "local", so it must be selected explicitly rather than
# relying on the kubeconfig's current-context.
# ---------------------------------------------------------------------------
_HARVESTER_KUBECONFIG="${HOME}/.kube/${ENVIRONMENT}-harvester.kubeconfig"
_HARVESTER_VMI_JSON=""
if [[ -f "${_HARVESTER_KUBECONFIG}" ]] && command -v kubectl >/dev/null 2>&1; then
  _HARVESTER_VMI_JSON="$(kubectl --kubeconfig "${_HARVESTER_KUBECONFIG}" --context local \
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

# Infrastructure IPs — nuc-00 is a single shared host on the homelab supernet;
# these are fixed supernet addresses, not per-environment (see Hardware.md).
export DNS1_IP="${SUPERNET_PREFIX}.10"
export ADMIN_IP="${SUPERNET_PREFIX}.10"
export LB_IP="${SUPERNET_PREFIX}.93"  # retired; kept for reference

# Admin web/repo server — this repo is a single shared checkout at
# /srv/www/htdocs/homelab.kubernerdes.com on nuc-00, serving all environments.
# There is no per-environment (${BASE_DOMAIN}) checkout.
export REPO_BASE="http://${ADMIN_IP}/homelab.kubernerdes.com"

# ---------------------------------------------------------------------------
# Harvester cluster
# ---------------------------------------------------------------------------
export HARVESTER_TOKEN="KentuckyHarvester"
export HARVESTER_PASSWORD="Passw0rd01"
export HARVESTER_VIP="${IP_PREFIX}.100"
export HARVESTER_HOSTNAME="harvester.${BASE_DOMAIN}"
# Let's Encrypt account email (expiry notices). The certificate itself is
# enabled per environment with HARVESTER_CERT=letsencrypt in env.d/.
export ACME_EMAIL="${ACME_EMAIL:-cloudxabide@gmail.com}"
export NUC01_IP="${IP_PREFIX}.101"
export NUC02_IP="${IP_PREFIX}.102"
export NUC03_IP="${IP_PREFIX}.103"

# ---------------------------------------------------------------------------
# RKE2 cluster — Rancher Manager
#   onprem — VIP is the Harvester load balancer; node IPs come from Harvester VMIs
#   aws    — single node (rancher-01), no load balancer: VIP is its private
#            IP. Values come from the OpenTofu outputs file (AWS_OUTPUTS_FILE),
#            written on nuc-00 after `tofu apply` with:
#              tofu -chdir=OpenTofu/aws output -json > "${AWS_OUTPUTS_FILE}"
#            Reading a file (not running tofu here) keeps env.sh free of AWS
#            credentials and state access. Output names it expects:
#              rancher_vip      (string)
#              rancher_node_ips (list of strings, rancher-01 first)
# RANCHER_HOSTNAME is the same in both cases; DNS decides where it points.
# RANCHER_REPLICAS follows the node count (Rancher helm chart replicas).
# ---------------------------------------------------------------------------
export RANCHER_HOSTNAME="rancher.${BASE_DOMAIN}"
export AWS_OUTPUTS_FILE="${AWS_OUTPUTS_FILE:-${HOME}/.config/homelab/${ENVIRONMENT}-aws-outputs.json}"

aws_output() {
  # aws_output <jq filter> — read a value from the OpenTofu outputs file
  [[ -f "${AWS_OUTPUTS_FILE}" ]] || { echo ""; return 0; }
  jq -r "$1 // empty" "${AWS_OUTPUTS_FILE}" 2>/dev/null || echo ""
}

if [[ "${RANCHER_LOCATION}" == "aws" ]]; then
  [[ -f "${AWS_OUTPUTS_FILE}" ]] || \
    echo "WARN: ${AWS_OUTPUTS_FILE} not found — RANCHER_VIP and node IPs will be empty" >&2
  export RANCHER_VIP="$(aws_output '.rancher_vip.value')"
  export RANCHER_REPLICAS="1"
  export RANCHER_NODE_01="$(aws_output '.rancher_node_ips.value[0]')"
  export RANCHER_NODE_02="$(aws_output '.rancher_node_ips.value[1]')"
  export RANCHER_NODE_03="$(aws_output '.rancher_node_ips.value[2]')"
else
  export RANCHER_VIP="${IP_PREFIX}.30"
  export RANCHER_REPLICAS="3"
  export RANCHER_NODE_01="$(harvester_vm_ip "rancher-01")"
  export RANCHER_NODE_02="$(harvester_vm_ip "rancher-02")"
  export RANCHER_NODE_03="$(harvester_vm_ip "rancher-03")"
fi

# ---------------------------------------------------------------------------
# RKE2 cluster — Observability (provisioned by Rancher Manager)
# ---------------------------------------------------------------------------
export OBS_VIP="${IP_PREFIX}.40"
export OBS_HOSTNAME="observability.${BASE_DOMAIN}"
export OBS_TLS_SECRET="tls-observability-ingress"
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

export ENCLAVE_RANCHER_VIP="${_ENCLAVE_PFX}.30"
export ENCLAVE_RANCHER_NODE_01="${_ENCLAVE_PFX}.31"
export ENCLAVE_RANCHER_NODE_02="${_ENCLAVE_PFX}.32"
export ENCLAVE_RANCHER_NODE_03="${_ENCLAVE_PFX}.33"

export ENCLAVE_OBS_VIP="${_ENCLAVE_PFX}.40"
export ENCLAVE_OBS_NODE_01="${_ENCLAVE_PFX}.41"
export ENCLAVE_OBS_NODE_02="${_ENCLAVE_PFX}.42"
export ENCLAVE_OBS_NODE_03="${_ENCLAVE_PFX}.43"

export ENCLAVE_APPS_VIP="${_ENCLAVE_PFX}.50"

export COMMUNITY_RANCHER_VIP="${_COMMUNITY_PFX}.30"
export COMMUNITY_RANCHER_NODE_01="${_COMMUNITY_PFX}.31"
export COMMUNITY_RANCHER_NODE_02="${_COMMUNITY_PFX}.32"
export COMMUNITY_RANCHER_NODE_03="${_COMMUNITY_PFX}.33"

export COMMUNITY_OBS_VIP="${_COMMUNITY_PFX}.40"
export COMMUNITY_OBS_NODE_01="${_COMMUNITY_PFX}.41"
export COMMUNITY_OBS_NODE_02="${_COMMUNITY_PFX}.42"
export COMMUNITY_OBS_NODE_03="${_COMMUNITY_PFX}.43"

export COMMUNITY_APPS_VIP="${_COMMUNITY_PFX}.50"

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
