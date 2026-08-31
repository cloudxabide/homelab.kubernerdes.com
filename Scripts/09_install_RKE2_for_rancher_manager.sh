#!/bin/bash

# TODO
#   get the IPs for the nodes from Harvester API call

echo "Read this script - it needs to be done manually still at this time"

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
