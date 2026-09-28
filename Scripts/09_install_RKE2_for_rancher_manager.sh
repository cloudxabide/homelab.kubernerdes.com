#!/bin/bash

# TODO
#   get the IPs for the nodes from Harvester API call

echo "Read this script - it needs to be done manually still at this time"

# Check if ENVIRONMENT is set, and if not, set it to community
ENVIRONMENT="${ENVIRONMENT:-community}"

# Not currently used — NODES is populated from Harvester via kubectl in
# run_this_script instead. Left as-is for reference/fallback.
create_node_array() {
### BEGIN - REPLACE THIS EVENTUALLY ###
PREFIX="10.10.12"
HOST_IDS="165 163 164"

NODES=()
for n in $HOST_IDS; do
  NODES+=("${PREFIX}.${n}")
done
printf '%s\n' "${NODES[@]}"
### END - REPLACE THIS EVENTUALLY ###
}

run_this_script() {
# Rancher-node IPs, resolved from Harvester. VMIs only exist under the
# kubeconfig's "local" context (see Scripts/env.sh), not "rancher".
mapfile -t NODES < <(KUBECONFIG="${HOME}/.kube/${ENVIRONMENT}-harvester.kubeconfig" \
  kubectl --context local get virtualmachineinstances -A -o json \
  | jq -r '[.items[] | select(.metadata.name | startswith("rancher")) | {name: .metadata.name, ip: (.status.interfaces[0].ipAddress // "")}] | sort_by(.name)[] | .ip')
printf '%s\n' "${NODES[@]}"

for NODE in ${NODES[@]}; do ssh-keygen -R $NODE -f /home/mansible/.ssh/known_hosts; done
for NODE in ${NODES[@]}; do ssh -i ~/.ssh/id_rsa-${ENVIRONMENT} -o StrictHostKeyChecking=accept-new sles@$NODE "uptime"; done
for NODE in ${NODES[@]}; do scp -i ~/.ssh/id_rsa-${ENVIRONMENT} install_RKE2* sles@$NODE:; done
for NODE in ${NODES[@]}; do ssh -i ~/.ssh/id_rsa-${ENVIRONMENT} -t sles@$NODE "sudo ENVIRONMENT=${ENVIRONMENT} bash -i ./install_RKE2.sh"; done

for NODE in $NODES; do ssh -t  $NODE "sudo shutdown now -r"; done
# Grab the kubeconfig from the first node in the list
scp -i ~/.ssh/id_rsa-${ENVIRONMENT} sles@${NODES%% *}:.kube/config ~/.kube/${ENVIRONMENT}-rancher.kubeconfig
config
}

exit 0
