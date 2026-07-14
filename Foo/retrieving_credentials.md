
## Harvester
Harvester embeds Rancher for auth — SSH to the Harvester node first, then run against the local kubeconfig:
```
export KUBECONFIG=~/.kube/community-harvester.kubeconfig
kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}{{ "\n" }}'
```

### Update Harvester password
Harvester uses the embedded Rancher admin user. Reset via the Rancher exec method below (from the Harvester node):
```
export KUBECONFIG=~/.kube/community-harvester.kubeconfig
kubectl -n cattle-system exec \
  $(kubectl -n cattle-system get pods -l app=rancher --no-headers | head -1 | awk '{print $1}') \
  -- reset-password
```

---

## Rancher Manager
```
export KUBECONFIG=~/.kube/community-rancher.kubeconfig
kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}{{ "\n" }}'
```

### Update Rancher password
```
export KUBECONFIG=~/.kube/community-rancher.kubeconfig
kubectl -n cattle-system exec \
  $(kubectl -n cattle-system get pods -l app=rancher --no-headers | head -1 | awk '{print $1}') \
  -- reset-password
```

---

## Security (NeuVector)
```
export KUBECONFIG=~/.kube/community-apps.kubeconfig
kubectl get secret --namespace cattle-neuvector-system neuvector-bootstrap-secret -o go-template='{{ .data.bootstrapPassword|base64decode}}{{ "\n" }}'
```

### Update NeuVector password
NeuVector password changes are done via the REST API (no kubectl exec method):
```
# Replace <current_password> and <new_password>
curl -k -X PATCH https://<neuvector-ui>:8443/v1/auth \
  -H 'Content-Type: application/json' \
  -d '{"password":{"username":"admin","password":"<current_password>","new_password":"<new_password>"}}'
```

---

## Observability (StackState)
StackState admin password is set at Helm deploy time. Retrieve from the generated secret:
```
export KUBECONFIG=~/.kube/community-observability.kubeconfig

# Secret name may vary by chart version — check with:
kubectl get secrets -n stackstate | grep -i admin

# Then retrieve (replace <secret-name>):
kubectl get secret --namespace stackstate <secret-name> -o go-template='{{.data.adminPassword|base64decode}}{{ "\n" }}'
```

### Update StackState password
StackState password changes are managed via the StackState CLI or UI. Via Helm upgrade:
```
export KUBECONFIG=~/.kube/community-observability.kubeconfig
helm upgrade stackstate stackstate/stackstate \
  --namespace stackstate \
  --reuse-values \
  --set stackstate.adminPassword=<new_password>
```

## Generic 
 
Dump ALL the "secrets"
```
for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
  echo "=== Namespace: $ns ==="
  kubectl get secrets -n $ns -o name | while read secret; do
    echo "  Secret: $secret"
    kubectl get $secret -n $ns -o go-template='{{range $k,$v := .data}}  {{$k}}: {{$v|base64decode}}{{"\n"}}{{end}}' 2>/dev/null
  done
done
```
