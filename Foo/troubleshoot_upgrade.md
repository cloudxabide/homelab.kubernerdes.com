# Troubleshooting Upgrade


```
  # Upgrade progress (the authoritative CR)
  kubectl --context harvester get upgrades.harvesterhci.io -A
  kubectl --context harvester get upgrades.harvesterhci.io <name> -n harvester-system -o yaml

  # Node versions (won't move until the CR advances)
  kubectl --context harvester get nodes -o wide

  # What's actually running/broken
  kubectl --context harvester get pods -n harvester-system
  kubectl --context harvester get events -n harvester-system --sort-by=.lastTimestamp

  # The stuck PVC/DataVolume
  kubectl --context harvester get pvc -n harvester-system
  kubectl --context harvester get datavolume -n harvester-system <name> -o yaml

  # Confirm it's not a real space shortage
  kubectl --context harvester get nodes.longhorn.io -n longhorn-system \
    -o custom-columns=NAME:.metadata.name,STORAGE_AVAIL:.status.diskStatus
```

## Delete attempted upgrade
```
kubectl --context harvester delete upgrades.harvesterhci.io hvst-upgrade-nz6q4 -n harvester-system)
```


  Filed bugs:
  - harvester/harvester#11143 — "v1.8.0 upgrade to v1.8.1 not working because of repeated importer crash (OOM killed)" — near-identical symptom: importer OOM-kills
    during qemu-img convert, then miscalculates available space on retry due to leftover partial /data.
  - harvester/harvester#10056 — "v1.7.1 to v1.8.0 upgrade blocked by CDI ISO image downloading" — same "PVC too small vs. actual available" pattern. Notably, this
    one is tagged as requiring backport to v1.7.2 and v1.8.2 — meaning the fix apparently didn't fully land, or doesn't cover the specific edge case we hit.

  Both are referenced from the official troubleshooting section of Harvester's own docs: Upgrade from v1.7.x to v1.8.x.

  Official fix path (per the doc, matches what I proposed): stop the upgrade, bump the CDI importer's memory limit via the harvester ManagedChart
  (spec.values.cdi.spec.config.podResourceRequirements.limits.memory, suggested 4G), retry, then remove the override afterward. That's arguably cleaner than my
  PVC-resize idea since it addresses the actual OOM root cause rather than working around the symptom. Want me to go that route instead?

```
6m10s       Normal    Pulled                        pod/importer-prime-926f72f7-080b-4b87-8cd8-f34353123152                                                               Container image "registry.suse.com/suse/sles/15.7/cdi-importer:1.64.0-150700.9.6.1" already present on machine and can be accessed by the pod
6m10s       Normal    Created                       pod/importer-prime-926f72f7-080b-4b87-8cd8-f34353123152                                                               Container created
6m10s       Normal    Started                       pod/importer-prime-926f72f7-080b-4b87-8cd8-f34353123152                                                               Container started
6m19s       Warning   BackOff                       pod/importer-prime-926f72f7-080b-4b87-8cd8-f34353123152                                                               Back-off restarting failed container importer in pod importer-prime-926f72f7-080b-4b87-8cd8-f34353123152_harvester-system(47147291-939e-4f0e-b35e-453d07a1d137)
4m25s       Normal    Killing                       pod/importer-prime-926f72f7-080b-4b87-8cd8-f34353123152                                                               Stopping container importer
29m         Warning   ErrImportFailed               persistentvolumeclaim/prime-14f2f48e-5426-4ec6-a29f-88b8bb7d804d                                                      Unable to process data: Unable to convert source data to target format: virtual image size 8232370176 is larger than the reported available storage 6541017088. A larger PVC is required
```
