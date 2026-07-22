# SUSE Observability - Client Registration - Lab Version

# NOTE: NOTE: NOTE
#   YOU NEED TO UPDATE stackstate.cluster.name to the value you entered when creating the stackpack
```
CLUSTER_NAME=rancher
ENVIRONMENT=community
export KUBECONFIG=~/.kube/${ENVIRONMENT}-${CLUSTER_NAME}.kubeconfig
kubectl get nodes

helm repo add suse-observability https://charts.rancher.com/server-charts/prime/suse-observability
helm repo update

# bail if the SERVICE_TOKEN is not set
[ -z $SERVICE_TOKEN ] && { echo "Error: you need to set SERVICE_TOKEN before you can proceed"; break; }

helm upgrade --install \
--namespace suse-observability \
--create-namespace \
--set-string 'stackstate.apiKey'=$SERVICE_TOKEN \
--set-string 'stackstate.cluster.name'=$CLUSTER_NAME \
--set-string 'stackstate.url'=https://observability.${ENVIRONMENT}.kubernerdes.com/receiver/stsAgent  \
--set 'nodeAgent.skipKubeletTLSVerify'=true \
--set-string 'global.skipSslValidation'=true \
--set 'nodeAgent.containers.processAgent.resources.limits.cpu'=200m \
--set 'nodeAgent.containers.processAgent.resources.limits.memory'=500Mi \
--set 'nodeAgent.containers.processAgent.resources.requests.cpu'=50m \
--set 'nodeAgent.containers.processAgent.resources.requests.memory'=200Mi \
suse-observability-agent suse-observability/suse-observability-agent
```

Note: the last four `--set` flags (processAgent resources) raise the process-agent
container's default limits (cpu: 125m / memory: 400Mi). Under sustained process-event
load those defaults are too tight — the container gets CPU-throttled, can't drain its
netlink process-event socket in time ("no buffer space available"), and eventually
crashes/OOMs; each restart triggers a full process/binary rescan that saturates host
disk I/O. Observed on a Harvester node 2026-07-22: disk ~88% busy, process-agent alone
reading ~175MB/s, recurring every couple hours until the limits were raised to match
the chart's own documented ceiling (nodeAgent.scaling.autoscalerLimits.processAgent.maximum).
Confirmed stable for 4+ hours after the change.

If you want to see the command with strings populated
```
cat << EOF 
helm upgrade --install \
--namespace suse-observability \
--create-namespace \
--set-string 'stackstate.apiKey'=$SERVICE_TOKEN \
--set-string 'stackstate.cluster.name'=$CLUSTER_NAME \
--set-string 'stackstate.url'=https://observability.${ENVIRONMENT}.kubernerdes.com/receiver/stsAgent  \
--set 'nodeAgent.skipKubeletTLSVerify'=true \
--set-string 'global.skipSslValidation'=true \
--set 'nodeAgent.containers.processAgent.resources.limits.cpu'=200m \
--set 'nodeAgent.containers.processAgent.resources.limits.memory'=500Mi \
--set 'nodeAgent.containers.processAgent.resources.requests.cpu'=50m \
--set 'nodeAgent.containers.processAgent.resources.requests.memory'=200Mi \
suse-observability-agent suse-observability/suse-observability-agent
EOF
```

## Original/default
The following is what you would see as a default registration string
```
helm repo add suse-observability https://charts.rancher.com/server-charts/prime/suse-observability
helm repo update
```
then...
```
helm upgrade --install \
--namespace suse-observability \
--create-namespace \
--set-string 'stackstate.apiKey'=$SERVICE_TOKEN \
--set-string 'stackstate.cluster.name'='rancher' \
--set-string 'stackstate.url'='https://observability.suse-demo-aws.kubernerdes.com/receiver/stsAgent' \
--set 'nodeAgent.containers.processAgent.resources.limits.cpu'=200m \
--set 'nodeAgent.containers.processAgent.resources.limits.memory'=500Mi \
--set 'nodeAgent.containers.processAgent.resources.requests.cpu'=50m \
--set 'nodeAgent.containers.processAgent.resources.requests.memory'=200Mi \
suse-observability-agent suse-observability/suse-observability-agent

