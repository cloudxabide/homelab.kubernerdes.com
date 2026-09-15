# Upgrades for Community/SUSE/RGS Software

> [!NOTE]
> Three distinct upgrade paths live in this homelab, and it's easy to conflate them because they stack on top of each other physically. They are **independent** — you can bump one without touching the others — but they are **related**: Harvester is the hypervisor everything else runs as VMs on top of, RKE2 is the Kubernetes distribution those Rancher Manager VMs run, and Rancher Manager is just a Helm release deployed onto that RKE2 cluster.

## Overview

| Path | What it upgrades | Where it runs | Kubeconfig | How it's triggered |
|:-----|:------------------|:---------------|:-----------|:--------------------|
| [Harvester](#1-harvester-upgrade) | The HCI/hypervisor layer itself (nodes `nuc-01`/`nuc-02`/`nuc-03`) | Harvester management cluster | `~/.kube/${ENVIRONMENT}-harvester.kubeconfig` (`$KUBECONFIG_HARVESTER`) | Harvester UI → Advanced → Upgrade, or an `upgrades.harvesterhci.io/Upgrade` CR |
| [RKE2](#2-rke2-upgrade) | The Kubernetes distro under Rancher Manager (`rancher-01`/`02`/`03` VMs) | RKE2 cluster hosting Rancher | `~/.kube/${ENVIRONMENT}-rancher.kubeconfig` (`$KUBECONFIG_RANCHER`) | `install-rke2.sh` re-run per node with `INSTALL_RKE2_VERSION` pinned, `systemctl restart rke2-server` |
| [Rancher Manager](#3-rancher-manager-upgrade) | The Rancher application (Helm release `rancher` in `cattle-system`) | Same RKE2 cluster as above | `~/.kube/${ENVIRONMENT}-rancher.kubeconfig` (`$KUBECONFIG_RANCHER`) | `helm upgrade --install rancher ...` |

Recommended order when bumping more than one at a time: **Harvester → RKE2 → Rancher Manager** — bottom of the stack first. Always check the [Rancher/RKE2/Kubernetes support matrix](https://www.suse.com/suse-rancher/support-matrix/all-supported-versions/) before jumping more than one minor version on any layer; Rancher Manager in particular refuses to manage an RKE2 version it doesn't recognize.

---

## 1. Harvester Upgrade

### Pre-Upgrade Checks

Run [`harvester/upgrade-helpers`'s `pre-check/v1.x/check.sh`](https://github.com/harvester/upgrade-helpers/tree/main/pre-check) before starting any Harvester upgrade. It checks host/certificate validity, storage space availability, Helm/Harvester bundle status, node health, CAPI cluster state, Longhorn volume and backing-image health, VM live-migration capability, pod status, kubeconfig secrets, and IP availability for storage/RWX — pass/fail/skip per check (`-v` for verbose, `-l` to log to a file). If anything fails, don't proceed.

https://github.com/harvester/upgrade-helpers/tree/main/pre-check/v1.x

```bash
ssh rancher@nuc-01.$ENVIRONMENT.$DOMAIN
sudo -i
mkdir -p ~/Developer/Projects; cd $_
curl -sLf https://raw.githubusercontent.com/harvester/upgrade-helpers/main/pre-check/v1.x/check.sh -o check.sh
chmod +x check.sh
./check.sh

```

Note: this checks cluster/storage/node health — it would **not** have caught the CDI importer memory-limit issue below, since that's a resource-limit default rather than a pre-existing cluster condition. Worth running regardless as the first line of defense for everything else.

Also confirm:
- All nodes `Ready` (`kubectl get nodes`) and no degraded Longhorn volumes (`kubectl get volumes.longhorn.io -A | grep -v healthy`).
- The target `Version` CR's `minUpgradableVersion` is satisfied by your current version (`kubectl get version.harvesterhci.io <target> -o jsonpath='{.spec.minUpgradableVersion}'`).
- Adequate free space on each node's default disk — the ISO import alone needs several GB of headroom beyond the ISO's own size (see the known issue below).

### Narrative

Kicked off from the Harvester UI (Virtual Machines → top-right → Support → or the dedicated Upgrade page), an upgrade creates an `Upgrade` custom resource in `harvester-system`. That CR drives a state machine visible via its `harvesterhci.io/upgradeState` label:

```
PreparingLoggingInfra → (image import) → PreparingNodes → UpgradingSystemServices → UpgradingNodes → Succeeded
```

Node upgrades within `UpgradingNodes` happen **sequentially, one node at a time** — each is cordoned, drained, rebooted into the new version, and rejoined before the next starts. For a 3-node control-plane/etcd cluster, budget ~10–15 minutes per node.

### Monitoring Commands

```bash
export KUBECONFIG_HARVESTER=~/.kube/${ENVIRONMENT}-harvester.kubeconfig

# The authoritative source of truth for progress
kubectl --kubeconfig "$KUBECONFIG_HARVESTER" get upgrades.harvesterhci.io -n harvester-system
kubectl --kubeconfig "$KUBECONFIG_HARVESTER" get upgrades.harvesterhci.io <name> -n harvester-system -o yaml

# Node versions (only change once UpgradingNodes reaches that node)
kubectl --kubeconfig "$KUBECONFIG_HARVESTER" get nodes -o wide

# ISO import progress (Phase 1 — see known issue below)
kubectl --kubeconfig "$KUBECONFIG_HARVESTER" get datavolume -n harvester-system

# Per-node "prepare" and OS-upgrade jobs (system-upgrade-controller Plans)
kubectl --kubeconfig "$KUBECONFIG_HARVESTER" get plans.upgrade.cattle.io -n cattle-system
kubectl --kubeconfig "$KUBECONFIG_HARVESTER" get pods -n cattle-system | grep apply-

kubectl --kubeconfig "$KUBECONFIG_HARVESTER" get events -n harvester-system --sort-by=.lastTimestamp
```

### Known Issue: CDI Importer OOM / "DataVolume too small to contain image"

Hit live during a `v1.8.1 → v1.8.2` upgrade in this environment. Symptom, during the very first phase (ISO import):

```
Unable to convert source data to target format: virtual image size <X> is larger
than the reported available storage <Y>. A larger PVC is required
```

**Root cause:** the CDI importer pod's memory limit (`2G` by default) isn't enough headroom for `qemu-img convert` on slower destination storage. It gets OOM-killed mid-conversion, leaves a partial file behind on the population PVC, and every retry recalculates "available storage" against a volume that's already partially full — so it fails faster each time rather than succeeding.

Filed upstream:
- [harvester/harvester#11143](https://github.com/harvester/harvester/issues/11143) — v1.8.0→v1.8.1, same symptom
- [harvester/harvester#10056](https://github.com/harvester/harvester/issues/10056) — v1.7.1→v1.8.0, same symptom (tagged for backport to 1.7.2/1.8.2 — evidently didn't fully close the gap)

This is a general upstream Harvester/CDI bug, not RGS/gov-build specific — confirmed by the `Version` CR's `isoURL` pointing at `releases.rancher.com` (the community release channel), not an RGS-hardened source.

**Fix** (per [Harvester's own v1.7.x→v1.8.x upgrade docs](https://docs.harvesterhci.io/v1.8/upgrade/v1-7-x-to-v1-8-x/)):

```bash
# 1. Stop the stuck upgrade — deletes the Upgrade CR, DataVolume, and PVCs,
#    clearing the stale partial-import data. No node/VM data is touched.
kubectl --kubeconfig "$KUBECONFIG_HARVESTER" delete upgrades.harvesterhci.io <name> -n harvester-system

# 2. Raise the CDI importer's memory limit via the harvester ManagedChart
#    (this is what actually reconciles the CDI CR — patching CDIConfig
#    directly gets reverted since it's owned by the CDI operator)
kubectl --kubeconfig "$KUBECONFIG_HARVESTER" patch managedchart harvester -n fleet-local --type=merge \
  -p '{"spec":{"values":{"cdi":{"spec":{"config":{"podResourceRequirements":{"limits":{"memory":"4G"}}}}}}}}'

# 3. Confirm it propagated (takes a few seconds via Fleet reconcile)
kubectl --kubeconfig "$KUBECONFIG_HARVESTER" get cdi cdi -o jsonpath='{.spec.config.podResourceRequirements.limits.memory}'

# 4. Retry the upgrade from the UI.

# 5. Once it succeeds, remove the override (restores the 2G default):
kubectl --kubeconfig "$KUBECONFIG_HARVESTER" patch managedchart harvester -n fleet-local --type=json \
  -p '[{"op":"remove","path":"/spec/values/cdi"}]'
```

Don't bother resizing the population PVC (`prime-<uuid>`) directly as a workaround — the margin is often too thin (in this incident, ~5.46% free vs. a 6% required filesystem-overhead reserve) and the DataVolume spec is immutable once created anyway. The memory-limit fix addresses the actual root cause.

---

## 2. RKE2 Upgrade

This is the RKE2 Kubernetes distribution running on `rancher-01`/`02`/`03` — the VMs Rancher Manager itself is deployed onto (installed originally via `Scripts/install_RKE2.sh`). This is **not** Rancher-provisioning-managed (no `Cluster` object driving it); it's upgraded the same way it was installed — manually, per node, via the RKE2 install script.

### Narrative

All three nodes in this environment are `control-plane,etcd` (see `Scripts/install_RKE2.sh` — no separate worker pool for the Rancher cluster). That means **every** node upgrade risks etcd quorum if done carelessly — always upgrade one node at a time and confirm the cluster is healthy before moving to the next.

RKE2 does not support skipping minor versions in a single hop (e.g. don't go straight from `v1.33.x` to `v1.35.x`) — step through each minor version per the [RKE2 upgrade docs](https://docs.rke2.io/upgrade/upgrades).

### Example Commands

```bash
export KUBECONFIG_RANCHER=~/.kube/${ENVIRONMENT}-rancher.kubeconfig
kubectl --kubeconfig "$KUBECONFIG_RANCHER" get nodes -o wide   # current version baseline

# Per node (one at a time), from Scripts/install_RKE2.sh's own method:
ssh sles@rancher-01 "sudo systemctl stop rke2-server"
ssh sles@rancher-01 "curl -sfL https://get.rke2.io/install-rke2.sh | sudo INSTALL_RKE2_VERSION='v1.34.8+rke2r1' sh -"
ssh sles@rancher-01 "sudo systemctl restart rke2-server"

# Confirm the node rejoined healthy before moving to rancher-02, then rancher-03
kubectl --kubeconfig "$KUBECONFIG_RANCHER" get nodes -o wide
kubectl --kubeconfig "$KUBECONFIG_RANCHER" get pods -n kube-system | grep -v Running
```

If this cluster is later imported into Rancher's own provisioning (shows up under Cluster Management as a managed `local`/custom cluster rather than just an imported one), the version bump can instead be driven from the Rancher UI, which deploys `system-upgrade-controller` `Plan` objects (`rke2-server`/`rke2-agent`) — the exact same mechanism Harvester itself uses for its node OS upgrades, just a different Plan.

---

## 3. Rancher Manager Upgrade

Rancher Manager is a straight Helm release (see `Scripts/10_install_rancher_manager.sh`) — chart source and pin vary per `ENVIRONMENT` (`env.d/*.sh`):

| Environment | Chart | Repo |
|:------------|:------|:-----|
| community | `rancher-latest/rancher` | `releases.rancher.com/server-charts/latest` |
| prime | `rancher-prime/rancher` | `charts.rancher.com/server-charts/prime` |
| enclave | `rancher/rancher` | local Harbor mirror |

### Narrative

Upgrading is a `helm upgrade` bump of `RANCHER_VERSION` — but two things need checking **before** running it:
1. **RKE2/Kubernetes compatibility** — the target Rancher version must support the RKE2 version currently running (see the [support matrix](https://www.suse.com/suse-rancher/support-matrix/all-supported-versions/)). Upgrade RKE2 first if needed.
2. **cert-manager compatibility** — each Rancher release pins a supported cert-manager range; check the [Rancher upgrade docs](https://ranchermanager.docs.rancher.com/getting-started/installation-and-upgrade/upgrade) before bumping cert-manager independently.

Take a backup via the `rancher-backup` operator before upgrading — Rancher's own docs treat this as a hard prerequisite, not a suggestion.

### Example Commands

```bash
export KUBECONFIG_RANCHER=~/.kube/${ENVIRONMENT}-rancher.kubeconfig
export KUBECONFIG="$KUBECONFIG_RANCHER"

# Bump RANCHER_VERSION in Scripts/env.d/${ENVIRONMENT}.sh first, then:
helm repo update
helm upgrade --install rancher "${RANCHER_CHART_NAME}" \
  --version "${RANCHER_VERSION}" \
  --namespace cattle-system \
  --reuse-values

kubectl -n cattle-system rollout status deploy/rancher --timeout=300s
kubectl -n cattle-system get pods -l app=rancher
```

`--reuse-values` matters here — re-running the full install command from `10_install_rancher_manager.sh` verbatim would reapply `--set bootstrapPassword=...` and other first-install-only flags against a live system.

---

## References

**Harvester**
- [Upgrading Harvester](https://docs.harvesterhci.io/v1.8/upgrade/index/) — overview and general prerequisites
- [Upgrade from v1.7.x to v1.8.x](https://docs.harvesterhci.io/v1.8/upgrade/v1-7-x-to-v1-8-x/) — includes the CDI OOM troubleshooting section referenced above
- [harvester/harvester#11143](https://github.com/harvester/harvester/issues/11143), [#10056](https://github.com/harvester/harvester/issues/10056) — CDI importer OOM bug reports

**RKE2**
- [RKE2 Upgrades](https://docs.rke2.io/upgrade/upgrades) — manual and automated upgrade methods, version-skew rules

**Rancher Manager**
- [Rancher Upgrades](https://ranchermanager.docs.rancher.com/getting-started/installation-and-upgrade/upgrade) — Helm-based upgrade procedure, backup prerequisite
- [SUSE Rancher/RKE2/Kubernetes Support Matrix](https://www.suse.com/suse-rancher/support-matrix/all-supported-versions/) — cross-version compatibility for all three layers
