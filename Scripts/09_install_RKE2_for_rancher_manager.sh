#!/bin/bash

# TODO
#   [DONE] get the IPs for the nodes from Harvester API call 
#   test that the current KUBECONFIG scoped in this script works
#   Automate the reboot of the nodes post-RKE2 install

echo "Read this script - it needs to be done manually still at this time"

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
  mapfile -t NODES < <(jq -r '.rancher_node_ips.value[]' "${AWS_OUTPUTS_FILE}")
  # install_RKE2.sh would otherwise put the on-prem VIP (${IP_PREFIX}.30) and
  # rancher.<env> name in tls-san
  RANCHER_VIP="$(jq -r '.rancher_vip.value' "${AWS_OUTPUTS_FILE}")"
  RANCHER_HOSTNAME="$(jq -r '.rancher_hostname.value' "${AWS_OUTPUTS_FILE}")"
else
mapfile -t NODES < <(KUBECONFIG="${HOME}/.kube/${ENVIRONMENT}-harvester.kubeconfig" \
  kubectl --context local get virtualmachineinstances -A -o json \
  | jq -r '[.items[] | select(.metadata.name | startswith("rancher")) | {name: .metadata.name, ip: (.status.interfaces[0].ipAddress // "")}] | sort_by(.name)[] | .ip')
fi

echo "Discovered rancher node IPs:"
printf '  %s\n' "${NODES[@]}"
sleep 5

SSH_KEY="${HOME}/.ssh/id_rsa-${ENVIRONMENT}"

for NODE in "${NODES[@]}"; do ssh-keygen -R "$NODE" -f "${HOME}/.ssh/known_hosts"; done
for NODE in "${NODES[@]}"; do ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new sles@"$NODE" "uptime"; done
for NODE in "${NODES[@]}"; do scp -i "$SSH_KEY" install_RKE2* sles@"$NODE":; done
# On SL-Micro, install_RKE2.sh reboots the node itself (transactional update),
# so each ssh session ends with the connection dropping — that is expected.
for NODE in "${NODES[@]}"; do ssh -i "$SSH_KEY" -t sles@"$NODE" "sudo ENVIRONMENT=${ENVIRONMENT} RANCHER_VIP=${RANCHER_VIP:-} RANCHER_HOSTNAME=${RANCHER_HOSTNAME:-} bash -i ./install_RKE2.sh"; done

# Wait for each node to come back, then run the postboot step install_RKE2.sh
# left behind (it writes ~sles/.kube/config). Non-SL-Micro nodes ran it inline
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

# Grab the kubeconfig from the first node in the list
scp -i "$SSH_KEY" sles@"${NODES[0]}":.kube/config ~/.kube/${ENVIRONMENT}-rancher.kubeconfig
export KUBECONFIG=~/.kube/${ENVIRONMENT}-rancher.kubeconfig
chmod 0644 $KUBECONFIG
kubectl get nodes
}

exit 0
