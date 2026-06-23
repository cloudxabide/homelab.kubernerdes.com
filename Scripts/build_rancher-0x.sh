# Cut-and-paste reference — not designed for unattended execution.
#
# Reference: https://docs.rke2.io/install/quickstart
#            https://ranchermanager.docs.rancher.com/how-to-guides/new-user-guides/kubernetes-cluster-setup/rke2-for-rancher
#
# Topology:
#   3 x SL-Micro 6.2 VMs (rancher-01/02/03) on Harvester, DHCP-assigned IPs
#   Harvester load balancer: lb-rancher  VIP=10.10.14.30  ports 80,443,6443,9345
#   Backend selector: harvesterhci.io/vmNamePrefix: rancher
#   Rancher hostname: rancher.community.kubernerdes.com

# SU to root
sudo su -

# ── Variables ────────────────────────────────────────────────────────────────
#export MY_RKE2_VERSION=v1.32.5+rke2r1
export MY_RKE2_VERSION=v1.35.5+rke2r2 # June 2026
export MY_RKE2_TOKEN=Waggoner
export MY_RKE2_VIP=10.10.14.30
export MY_RANCHER_HOSTNAME=rancher.community.kubernerdes.com

# ── RKE2 install ─────────────────────────────────────────────────────────────
# Run on ALL nodes (rancher-01, rancher-02, rancher-03)

curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=${MY_RKE2_VERSION} sh -

mkdir -p /etc/rancher/rke2

# ── Node-specific config ──────────────────────────────────────────────────────
# Choose the correct block for each node:

## rancher-01 (first server — cluster-init)
cat << EOF > /etc/rancher/rke2/config.yaml
token: ${MY_RKE2_TOKEN}
tls-san:
  - ${MY_RKE2_VIP}
  - ${MY_RANCHER_HOSTNAME}
EOF

## rancher-02 and rancher-03 (additional servers — join via VIP:9345)
cat << EOF > /etc/rancher/rke2/config.yaml
server: https://${MY_RKE2_VIP}:9345
token: ${MY_RKE2_TOKEN}
tls-san:
  - ${MY_RKE2_VIP}
  - ${MY_RANCHER_HOSTNAME}
EOF

# ── Start RKE2 ───────────────────────────────────────────────────────────────
systemctl enable rke2-server.service
systemctl start rke2-server.service

# Watch progress (takes ~2-3 min on first node)
journalctl -u rke2-server -f

# ── Kubeconfig (run on rancher-01 after RKE2 is up) ──────────────────────────
mkdir -p ~/.kube
cp /etc/rancher/rke2/rke2.yaml ~/.kube/config
sed -i "s/127.0.0.1/${MY_RKE2_VIP}/g" ~/.kube/config
chown $(whoami) ~/.kube/config
export KUBECONFIG=~/.kube/config
export PATH=$PATH:/var/lib/rancher/rke2/bin

mkdir ~sles/.kube
cp ~/.kube/config ~sles/.kube/community-rancher.kubeconfig

chown -R sles:sles ~sles/.kube

# Verify all 3 nodes are Ready before proceeding
kubectl get nodes -o wide

# Verify TLS SANs include the VIP and hostname
openssl s_client -connect 127.0.0.1:6443 -showcerts </dev/null 2>/dev/null | openssl x509 -noout -text | grep -A1 "Subject Alternative"

# ── Helm + Rancher (run from rancher-01 or your local machine with kubeconfig) ─
# Requires: helm, kubectl with kubeconfig pointing at 10.10.14.30

export KUBECONFIG=~/.kube/config
export PATH=$PATH:/var/lib/rancher/rke2/bin

CERTMGR_VERSION=v1.20.0
RANCHER_HOSTNAME=rancher.community.kubernerdes.com

#helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update

helm repo add jetstack https://charts.jetstack.io
helm repo update

kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/${CERTMGR_VERSION}/cert-manager.crds.yaml

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version ${CERTMGR_VERSION}

# Wait for cert-manager to be ready
kubectl rollout status deploy/cert-manager -n cert-manager
kubectl rollout status deploy/cert-manager-webhook -n cert-manager

# TODO: make the search retrieve teh version programatically
helm search repo rancher-stable/rancher --versions
kubectl create namespace cattle-system
helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --set hostname=${RANCHER_HOSTNAME} \
  --set replicas=3 \
  --version=2.14.2 \
  --set bootstrapPassword='Passw0rd01##'

# Watch rollout
kubectl rollout status deploy/rancher -n cattle-system

# Print the setup URL with bootstrap password
echo "https://${RANCHER_HOSTNAME}/dashboard/?setup=$(kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}')"

## ── Troubleshooting ──────────────────────────────────────────────────────────
# RKE2 service logs
# journalctl -xeu rke2-server.service

# Rancher pod status
# kubectl -n cattle-system get pods -l app=rancher -o wide
# kubectl -n cattle-system logs -l app=rancher --tail=50

# Cluster health
# kubectl get nodes -o wide
# kubectl get pods -A | grep -v Running | grep -v Completed

# Verify LB endpoint is reachable on all ports
# for port in 80 443 6443 9345; do
#   nc -zv ${MY_RKE2_VIP} $port && echo "port $port OK" || echo "port $port FAIL"
# done

# Service/pod CIDRs
# echo '{"apiVersion":"v1","kind":"Service","metadata":{"name":"tst"},"spec":{"clusterIP":"1.1.1.1","ports":[{"port":443}]}}' | kubectl apply -f - 2>&1 | sed 's/.*valid IPs is //'
# kubectl get nodes -o jsonpath='{.items[*].spec.podCIDR}'
