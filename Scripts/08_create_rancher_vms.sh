#!/bin/bash
set -euo pipefail

# 08_create_rancher_vms.sh — Create the Rancher Manager VMs and their load balancer
#
# Prerequisites:
#   - 07_post_configure_harvester.sh has run (VM network, local StorageClass,
#     Rancher image on that StorageClass)
#   - KUBECONFIG set to Harvester kubeconfig:
#       export KUBECONFIG=/path/to/harvester-kubeconfig.yaml
#   - Run from nuc-00 (from the repo checkout — the cloud-init template is
#     read from Files/CloudConfigurationTemplates/ next to this script)
#
# What this does:
#   1. Verifies the Rancher image is downloaded and its StorageClass really is
#      1 replica / best-effort (aborts otherwise — this is the trap that put the
#      previous build's etcd on 3 remote replicas)
#   2. Creates namespace, SSH keypair, and per-VM cloud-init secrets
#   3. Creates rancher-01/02/03, each pinned to its own node (RANCHER_VM_PLACEMENT)
#      with the instance label the load balancer selects on
#   4. Creates the IP pool + load balancer for RANCHER_VIP (80/443/6443/9345)
#   5. Waits for the VMs, then checks node placement, instance label, disk
#      replica count/locality, and load balancer backends
#
# The VM spec mirrors the hand-built rancher-01..03 from the 2026-10-13 rebuild.
# Deliberate differences from those hand-built VMs:
#   - MAC addresses are derived from "${ENVIRONMENT}-<vm>" instead of random,
#     so they are stable across rebuilds and can carry DHCP reservations
#   - disk/cloud-init secret names are <vm>-disk-0 / <vm>-cloudinit instead of
#     carrying a random suffix
#
# Safe to re-run: existing VMs are left alone (delete a VM to recreate it).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh"

for var in RANCHER_VM_NAMESPACE RANCHER_VM_PLACEMENT RANCHER_IMAGE_NAME VM_NETWORK_NAME \
           RANCHER_VM_CPU RANCHER_VM_MEMORY RANCHER_VM_DISK_SIZE RANCHER_VM_CLOUDINIT \
           RANCHER_VM_LABEL_KEY RANCHER_VM_LABEL_VALUE RANCHER_VIP; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: ${var} is not set — define it in Scripts/env.d/${ENVIRONMENT}.sh" >&2
    exit 1
  fi
done

CLOUDINIT_FILE="${REPO_ROOT}/Files/CloudConfigurationTemplates/${RANCHER_VM_CLOUDINIT}"
KEYPAIR_NAME="id-rsa"
KEYPAIR_PUBKEY_FILE="${SSH_KEY}.pub"
LB_NAME="lb-rancher"
IPPOOL_NAME="ippool-rancher"

# wait_for <description> <timeout-seconds> <command...>
# Re-runs the command every 5s until it succeeds or the timeout expires.
wait_for() {
  local desc="$1" timeout="$2"; shift 2
  local waited=0
  until "$@" >/dev/null 2>&1; do
    if (( waited >= timeout )); then
      echo "ERROR: timed out after ${timeout}s waiting for: ${desc}" >&2
      return 1
    fi
    sleep 5; waited=$((waited + 5))
  done
  echo "    ${desc} — ok"
}

# Stable, locally-administered unicast MAC (02:xx:xx:xx:xx:xx) from a string
mac_for() {
  local h
  h=$(printf '%s' "$1" | { md5sum 2>/dev/null || md5; } | cut -c1-10)
  echo "02:${h:0:2}:${h:2:2}:${h:4:2}:${h:6:2}:${h:8:2}"
}

b64() { base64 | tr -d '\n'; }

# ---------------------------------------------------------------------------
# 1. Rancher image + its StorageClass
# ---------------------------------------------------------------------------
echo "==> Checking image default/${RANCHER_IMAGE_NAME}"
if ! kubectl -n default get virtualmachineimage "${RANCHER_IMAGE_NAME}" >/dev/null 2>&1; then
  echo "ERROR: image default/${RANCHER_IMAGE_NAME} not found — run 07_post_configure_harvester.sh" >&2
  exit 1
fi
wait_for "image downloaded (progress 100)" 1800 \
  sh -c "kubectl -n default get virtualmachineimage ${RANCHER_IMAGE_NAME} -o jsonpath='{.status.progress}' | grep -qx 100"

IMAGE_SC=$(kubectl -n default get virtualmachineimage "${RANCHER_IMAGE_NAME}" -o jsonpath='{.status.storageClassName}')
IMAGE_SC_REPLICAS=$(kubectl get storageclass "${IMAGE_SC}" -o jsonpath='{.parameters.numberOfReplicas}')
IMAGE_SC_LOCALITY=$(kubectl get storageclass "${IMAGE_SC}" -o jsonpath='{.parameters.dataLocality}')
echo "    image StorageClass ${IMAGE_SC}: replicas=${IMAGE_SC_REPLICAS} dataLocality=${IMAGE_SC_LOCALITY}"
if [[ "${IMAGE_SC_REPLICAS}" != "1" || "${IMAGE_SC_LOCALITY}" != "best-effort" ]]; then
  echo "ERROR: image StorageClass is not 1 replica / best-effort — refusing to build etcd VMs on it" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Namespace, keypair, cloud-init secrets
# ---------------------------------------------------------------------------
echo "==> Namespace ${RANCHER_VM_NAMESPACE}"
kubectl create namespace "${RANCHER_VM_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

if [[ ! -f "${CLOUDINIT_FILE}" ]]; then
  echo "ERROR: cloud-init template not found: ${CLOUDINIT_FILE}" >&2
  exit 1
fi
USERDATA="$(cat "${CLOUDINIT_FILE}")"

SSH_NAMES_ANNOTATION=""
if [[ -f "${KEYPAIR_PUBKEY_FILE}" ]]; then
  PUBKEY="$(cat "${KEYPAIR_PUBKEY_FILE}")"
  echo "==> SSH keypair ${RANCHER_VM_NAMESPACE}/${KEYPAIR_NAME} (${KEYPAIR_PUBKEY_FILE})"
  kubectl apply -f - <<EOF
apiVersion: harvesterhci.io/v1beta1
kind: KeyPair
metadata:
  name: ${KEYPAIR_NAME}
  namespace: ${RANCHER_VM_NAMESPACE}
spec:
  publicKey: "${PUBKEY}"
EOF
  # Harvester's UI appends the selected keypair as a top-level block
  USERDATA="${USERDATA}
ssh_authorized_keys:
  - ${PUBKEY}"
  SSH_NAMES_ANNOTATION="harvesterhci.io/sshNames: '[\"${RANCHER_VM_NAMESPACE}/${KEYPAIR_NAME}\"]'"
else
  echo "    WARN: ${KEYPAIR_PUBKEY_FILE} not found — skipping keypair (template keys still apply)"
fi

# ---------------------------------------------------------------------------
# 3. VMs
# ---------------------------------------------------------------------------
VM_NAMES=()
for pair in ${RANCHER_VM_PLACEMENT}; do
  vm="${pair%%:*}"
  node="${pair##*:}"
  VM_NAMES+=("${vm}")
  mac="$(mac_for "${ENVIRONMENT}-${vm}")"
  disk="${vm}-disk-0"
  secret="${vm}-cloudinit"

  echo "==> VM ${RANCHER_VM_NAMESPACE}/${vm} -> node ${node}, MAC ${mac}"
  if kubectl -n "${RANCHER_VM_NAMESPACE}" get vm "${vm}" >/dev/null 2>&1; then
    echo "    already exists — leaving as-is"
    continue
  fi
  if ! kubectl get node "${node}" >/dev/null 2>&1; then
    echo "ERROR: node ${node} not found" >&2
    exit 1
  fi

  kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${secret}
  namespace: ${RANCHER_VM_NAMESPACE}
  labels:
    harvesterhci.io/cloud-init-template: harvester
type: secret
data:
  userdata: $(printf '%s\n' "${USERDATA}" | b64)
  networkdata: ""
EOF

  # Harvester creates the root PVC from this annotation; storageClassName must
  # be the image's own lh-<uid> class so the disk is cloned from the image.
  claim_templates=$(jq -cn --arg name "${disk}" --arg image "default/${RANCHER_IMAGE_NAME}" \
    --arg size "${RANCHER_VM_DISK_SIZE}" --arg sc "${IMAGE_SC}" \
    '[{metadata: {name: $name, annotations: {"harvesterhci.io/imageId": $image}},
       spec: {accessModes: ["ReadWriteMany"], resources: {requests: {storage: $size}},
              volumeMode: "Block", storageClassName: $sc}}]')

  kubectl apply -f - <<EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: ${vm}
  namespace: ${RANCHER_VM_NAMESPACE}
  labels:
    harvesterhci.io/creator: harvester
    harvesterhci.io/os: linux
  annotations:
    harvesterhci.io/mac-address: '{"default":"${mac}"}'
    harvesterhci.io/vmRunStrategy: RerunOnFailure
    harvesterhci.io/volumeClaimTemplates: '${claim_templates}'
spec:
  runStrategy: RerunOnFailure
  template:
    metadata:
      annotations:
        ${SSH_NAMES_ANNOTATION:-harvesterhci.io/sshNames: '[]'}
      labels:
        harvesterhci.io/vmName: ${vm}
        ${RANCHER_VM_LABEL_KEY}: ${RANCHER_VM_LABEL_VALUE}
    spec:
      hostname: ${vm}
      nodeSelector:
        kubernetes.io/hostname: ${node}
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: network.harvesterhci.io/mgmt
                    operator: In
                    values: ["true"]
      architecture: amd64
      evictionStrategy: LiveMigrateIfPossible
      terminationGracePeriodSeconds: 120
      domain:
        machine:
          type: q35
        cpu:
          cores: ${RANCHER_VM_CPU}
          sockets: 1
          threads: 1
          maxSockets: 1
        memory:
          guest: ${RANCHER_VM_MEMORY}
        resources:
          limits:
            cpu: "${RANCHER_VM_CPU}"
            memory: ${RANCHER_VM_MEMORY}
        features:
          acpi:
            enabled: true
        devices:
          disks:
            - name: disk-0
              bootOrder: 1
              disk:
                bus: virtio
            - name: cloudinitdisk
              disk:
                bus: virtio
          inputs:
            - name: tablet
              bus: usb
              type: tablet
          interfaces:
            - name: default
              model: virtio
              bridge: {}
              macAddress: ${mac}
      networks:
        - name: default
          multus:
            networkName: default/${VM_NETWORK_NAME}
      volumes:
        - name: disk-0
          persistentVolumeClaim:
            claimName: ${disk}
        - name: cloudinitdisk
          cloudInitNoCloud:
            secretRef:
              name: ${secret}
            networkDataSecretRef:
              name: ${secret}
EOF
done

# ---------------------------------------------------------------------------
# 4. IP pool + load balancer (backends selected by instance label)
# ---------------------------------------------------------------------------
echo "==> IP pool ${IPPOOL_NAME} (${RANCHER_VIP}) and load balancer ${LB_NAME}"
kubectl apply -f - <<EOF
apiVersion: loadbalancer.harvesterhci.io/v1beta1
kind: IPPool
metadata:
  name: ${IPPOOL_NAME}
spec:
  ranges:
    - subnet: ${SUBNET_CIDR}
      gateway: ${GATEWAY}
      rangeStart: ${RANCHER_VIP}
      rangeEnd: ${RANCHER_VIP}
  selector: {}
EOF

kubectl apply -f - <<EOF
apiVersion: loadbalancer.harvesterhci.io/v1beta1
kind: LoadBalancer
metadata:
  name: ${LB_NAME}
  namespace: ${RANCHER_VM_NAMESPACE}
spec:
  workloadType: vm
  ipam: pool
  ipPool: ${IPPOOL_NAME}
  backendServerSelector:
    ${RANCHER_VM_LABEL_KEY}:
      - ${RANCHER_VM_LABEL_VALUE}
  healthCheck: {}
  listeners:
    - name: http
      port: 80
      backendPort: 80
      protocol: TCP
    - name: https
      port: 443
      backendPort: 443
      protocol: TCP
    - name: k8s-api
      port: 6443
      backendPort: 6443
      protocol: TCP
    - name: rke2-service
      port: 9345
      backendPort: 9345
      protocol: TCP
EOF

# ---------------------------------------------------------------------------
# 5. Wait + verify
# ---------------------------------------------------------------------------
echo "==> Waiting for VMs to run and report an IP (guest agent)"
for vm in "${VM_NAMES[@]}"; do
  wait_for "${vm} running with IP" 900 \
    sh -c "kubectl -n ${RANCHER_VM_NAMESPACE} get vmi ${vm} -o jsonpath='{.status.phase} {.status.interfaces[0].ipAddress}' | grep -Eq '^Running [0-9]'"
done

echo "==> Verifying placement, labels, and disk locality"
FAILED=0
for pair in ${RANCHER_VM_PLACEMENT}; do
  vm="${pair%%:*}"
  node="${pair##*:}"
  vmi_json=$(kubectl -n "${RANCHER_VM_NAMESPACE}" get vmi "${vm}" -o json)
  vmi_node=$(jq -r '.status.nodeName' <<< "${vmi_json}")
  vmi_ip=$(jq -r '.status.interfaces[0].ipAddress // ""' <<< "${vmi_json}")
  vmi_label=$(jq -r --arg k "${RANCHER_VM_LABEL_KEY}" '.metadata.labels[$k] // ""' <<< "${vmi_json}")

  pvc=$(kubectl -n "${RANCHER_VM_NAMESPACE}" get vm "${vm}" \
    -o jsonpath='{.spec.template.spec.volumes[?(@.name=="disk-0")].persistentVolumeClaim.claimName}')
  lh_vol=$(kubectl -n "${RANCHER_VM_NAMESPACE}" get pvc "${pvc}" -o jsonpath='{.spec.volumeName}')
  replicas=$(kubectl -n longhorn-system get volumes.longhorn.io "${lh_vol}" -o jsonpath='{.spec.numberOfReplicas}')
  replica_nodes=$(kubectl -n longhorn-system get replicas.longhorn.io -l "longhornvolume=${lh_vol}" \
    -o jsonpath='{range .items[*]}{.spec.nodeID}{" "}{end}')

  status="ok"
  [[ "${vmi_node}" == "${node}" ]] || { status="FAIL: running on ${vmi_node}, expected ${node}"; FAILED=1; }
  [[ "${vmi_label}" == "${RANCHER_VM_LABEL_VALUE}" ]] || { status="FAIL: instance label missing"; FAILED=1; }
  [[ "${replicas}" == "1" ]] || { status="FAIL: disk has ${replicas} replicas"; FAILED=1; }
  # best-effort locality converges on its own, so a remote replica is only a warning
  if [[ "${status}" == "ok" && "${replica_nodes% }" != "${vmi_node}" ]]; then
    status="WARN: replica on '${replica_nodes% }' (best-effort will move it to ${vmi_node})"
  fi
  printf '    %-11s node=%-7s ip=%-15s replica=%-7s %s\n' "${vm}" "${vmi_node}" "${vmi_ip}" "${replica_nodes% }" "${status}"
done

wait_for "load balancer ${LB_NAME} has ${#VM_NAMES[@]} backends" 300 \
  sh -c "[ \"\$(kubectl -n ${RANCHER_VM_NAMESPACE} get loadbalancers.loadbalancer.harvesterhci.io ${LB_NAME} -o json | jq '.status.backendServers | length')\" -eq ${#VM_NAMES[@]} ]" \
  || FAILED=1

if (( FAILED )); then
  echo "==> Finished with problems — see FAIL lines above" >&2
  exit 1
fi

echo
echo "==> Done. Rancher VIP: ${RANCHER_VIP}"
echo "    Optional: add DHCP reservations on nuc-00 for the MACs above so etcd member IPs never change."
echo "    Next step: Scripts/09_install_RKE2_for_rancher_manager.sh"
