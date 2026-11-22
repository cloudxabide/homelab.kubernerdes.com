#!/bin/bash

# Installs RKE2 on the Rancher node(s) and fetches the kubeconfig.
# Usage (needs a terminal: install_RKE2.sh runs in an interactive ssh session):
#   ENVIRONMENT=prime ./09_install_RKE2_for_rancher_manager.sh                       # on-prem (Harvester VMs)
#   ENVIRONMENT=prime RANCHER_LOCATION=aws ./09_install_RKE2_for_rancher_manager.sh  # AWS (Scripts/awsctl build first)
# Sourcing the file defines run_this_script without running it.
#
# TODO
#   [DONE] get the IPs for the nodes from Harvester API call
#   [DONE] automate the reboot of the nodes post-RKE2 install (install_RKE2.sh + postboot step)
#   [DONE on AWS] kubeconfig fetch; re-test on-prem

# Check if ENVIRONMENT is set, and if not, set it to community
ENVIRONMENT="${ENVIRONMENT:-community}"

# Not currently used — NODES is populated from Harvester via kubectl in
# run_this_script instead. Left as-is for reference/fallback.
create_node_array() {
### BEGIN - THIS HAS BEEN REPLACED ###
PREFIX="10.10.12"
HOST_IDS="165 163 164"

NODES=()
for n in $HOST_IDS; do
  NODES+=("${PREFIX}.${n}")
done
printf '%s\n' "${NODES[@]}"
### END - THIS HAS BEEN REPLACED ###
}

run_this_script() {
# Rancher-node IPs, resolved from Harvester. VMIs only exist under the
# kubeconfig's "local" context (see Scripts/env.sh), not "rancher".
# RANCHER_LOCATION=aws: read them from the OpenTofu outputs file instead
# (same file and output name as Scripts/env.sh).
if [[ "${RANCHER_LOCATION:-onprem}" == "aws" ]]; then
  AWS_OUTPUTS_FILE="${AWS_OUTPUTS_FILE:-${HOME}/.config/homelab/${ENVIRONMENT}-aws-outputs.json}"
  if [[ ! -s "${AWS_OUTPUTS_FILE}" ]]; then
    echo "ERROR: ${AWS_OUTPUTS_FILE} not found (run Scripts/awsctl build first)" >&2
    return 1
  fi
  mapfile -t NODES < <(jq -r '.rancher_node_ips.value[]' "${AWS_OUTPUTS_FILE}")
  # install_RKE2.sh would otherwise put the on-prem VIP (${IP_PREFIX}.30) and
  # rancher.<env> name in tls-san
  RANCHER_VIP="$(jq -r '.rancher_vip.value' "${AWS_OUTPUTS_FILE}")"
  RANCHER_HOSTNAME="$(jq -r '.rancher_hostname.value' "${AWS_OUTPUTS_FILE}")"
else
mapfile -t NODES < <(KUBECONFIG="${HOME}/.kube/${ENVIRONMENT}-harvester.kubeconfig" \
  kubectl --context local --request-timeout="${HARVESTER_TIMEOUT:-5s}" get virtualmachineinstances -A -o json \
  | jq -r '[.items[] | select(.metadata.name | startswith("rancher")) | {name: .metadata.name, ip: (.status.interfaces[0].ipAddress // "")}] | sort_by(.name)[] | .ip')
fi

if [[ ${#NODES[@]} -eq 0 || -z "${NODES[0]}" ]]; then
  echo "ERROR: no rancher node IPs found for ENVIRONMENT=${ENVIRONMENT} RANCHER_LOCATION=${RANCHER_LOCATION:-onprem}" >&2
  return 1
fi

echo "Discovered rancher node IPs:"
printf '  %s\n' "${NODES[@]}"
sleep 5

SSH_KEY="${HOME}/.ssh/id_rsa-${ENVIRONMENT}"

for NODE in "${NODES[@]}"; do ssh-keygen -R "$NODE" -f "${HOME}/.ssh/known_hosts"; done
for NODE in "${NODES[@]}"; do ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new sles@"$NODE" "uptime"; done
for NODE in "${NODES[@]}"; do scp -i "$SSH_KEY" install_RKE2* sles@"$NODE":; done
# On a transactional OS (SL Micro), install_RKE2.sh reboots the node itself,
# so each ssh session ends with the connection dropping — that is expected.
for NODE in "${NODES[@]}"; do ssh -i "$SSH_KEY" -t sles@"$NODE" "sudo ENVIRONMENT=${ENVIRONMENT} RANCHER_VIP=${RANCHER_VIP:-} RANCHER_HOSTNAME=${RANCHER_HOSTNAME:-} bash -i ./install_RKE2.sh"; done

# Wait for each node to come back, then run the postboot step install_RKE2.sh
# left behind (it writes ~sles/.kube/config). Non-transactional nodes ran it inline
# and have no /var/lib/install_RKE2_postboot.sh, so they are skipped.
sleep 30
for NODE in "${NODES[@]}"; do
  echo "Waiting for ${NODE} to come back..."
  for _ in $(seq 1 60); do
    ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o BatchMode=yes sles@"$NODE" true 2>/dev/null && break
    sleep 10
  done
  ssh -i "$SSH_KEY" -t sles@"$NODE" \
    "if sudo test -f /var/lib/install_RKE2_postboot.sh; then sudo bash /var/lib/install_RKE2_postboot.sh; fi"
done

# Grab the kubeconfig from the first node in the list. The AWS Rancher gets its
# own file (same name as KUBECONFIG_RANCHER in Scripts/env.sh): on nuc-00,
# <env>-rancher.kubeconfig is the on-prem cluster, and root's copy is what the
# wildcard certificate renewal hook uses.
if [[ "${RANCHER_LOCATION:-onprem}" == "aws" ]]; then
  KUBECONFIG_FILE="${HOME}/.kube/${ENVIRONMENT}-rancher-aws.kubeconfig"
else
  KUBECONFIG_FILE="${HOME}/.kube/${ENVIRONMENT}-rancher.kubeconfig"
fi
scp -i "$SSH_KEY" sles@"${NODES[0]}":.kube/config "${KUBECONFIG_FILE}"
# RKE2 writes 127.0.0.1; the AWS node's API is only reachable at RANCHER_VIP
if [[ "${RANCHER_LOCATION:-onprem}" == "aws" ]]; then
  sed -i -e "s/127.0.0.1/${RANCHER_VIP}/g" "${KUBECONFIG_FILE}"
fi
export KUBECONFIG="${KUBECONFIG_FILE}"
chmod 0644 "$KUBECONFIG"
kubectl get nodes
}

# Run only when executed, not when sourced. cd so `scp install_RKE2*` finds
# the files no matter where the script is called from.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cd "$(dirname "$(readlink -f "$0")")" || exit 1
  run_this_script
fi
