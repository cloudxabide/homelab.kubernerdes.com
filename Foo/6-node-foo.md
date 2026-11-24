

Deploying rancher VMs
Key: node-role.kubernetes.io/control-plane 
Value: is set


## Storage network IPs

Run with the Harvester kubeconfig. Longhorn's instance-manager pods get a
second interface on the storage network (`lhnet1`, 192.168.128.0/24); this
lists one row per node: node, interface, IP, attachment.

```bash
export KUBECONFIG=~/.kube/prime-harvester.kubeconfig
kubectl -n longhorn-system get pods -l longhorn.io/component=instance-manager -o json \
 | jq -r '.items[] | .spec.nodeName as $n
     | (.metadata.annotations["k8s.v1.cni.cncf.io/network-status"] // "[]" | fromjson[])
     | select(.interface != "eth0") | "\($n)\t\(.interface)\t\(.ips | join(","))\t\(.name)"' | sort
```
