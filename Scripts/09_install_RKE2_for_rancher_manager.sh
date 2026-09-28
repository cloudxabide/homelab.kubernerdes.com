#!/bin/bash

# TODO
#   get the IPs for the nodes from Harvester API call

echo "Read this script - it needs to be done manually still at this time"

run_this_script() {
### BEGIN - REPLACE THIS EVENTUALLY ###
PREFIX="10.10.12"
HOST_IDS="165 163 164"

NODES=()
for n in $HOST_IDS; do
  NODES+=("${PREFIX}.${n}")
done
printf '%s\n' "${NODES[@]}"
### END - REPLACE THIS EVENTUALLY ###

for NODE in $NODES; do ssh-keygen -R $NODE -f /home/mansible/.ssh/known_hosts; doneK
for NODE in $NODES; do ssh -o StrictHostKeyChecking=accept-new sles@$NODE "uptime"; done
for NODE in $NODES; do scp install_RKE2* $NODE:; done
for NODE in $NODES; do ssh -t $NODE "sudo ENVIRONMENT=${ENVIRONMENT} bash -i ./install_RKE2.sh"; done

for NODE in $NODES; do ssh -t  $NODE "sudo shutdown now -r"; done
# Grab the kubeconfig from the first node in the list
scp ${NODES%% *}:.kube/config ~/.kube/${ENVIRONMENT}-rancher.kubeconfig
config
}
