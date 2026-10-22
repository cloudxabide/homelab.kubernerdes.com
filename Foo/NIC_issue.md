# gen10 NUC onboard NIC (eno1, e1000e) — "Hardware Unit Hang"

Under load the onboard I219 NIC on the gen10 NUCs (nuc-01/02/03) hangs: the
kernel logs `e1000e ... Detected Hardware Unit Hang` and the node drops off the
network until it is power-cycled. Hit on the prime build (nuc-01, 2026-10-22).
Confirmed driver: `e1000e` on eno1. The gen13 NUCs (enp86s0, igc) are not affected.

## Fix (automated)
`Scripts/07_post_configure_harvester.sh` applies it to every node in
`E1000E_FIX_GENS` (set to `gen10` in env.d/community.sh and prime.sh):

- **Persistent:** a Harvester `CloudInit` resource (`e1000e-offload-fix-gen10`)
  writes `/oem/99_e1000e_offload_fix.yaml` to nodes labeled
  `homelab.kubernerdes.com/nuc-gen=gen10`. At every boot it runs:
  ```
  ethtool -K eno1 tso off gso off gro off
  ethtool --set-eee eno1 eee off
  ```
- **Live:** TSO/GSO/GRO off on each running node (one at a time, via
  `kubectl debug node/...`), so no reboot is needed. EEE is left to the next
  boot because turning it off resets the adapter.

## Check
```
kubectl get cloudinits.node.harvesterhci.io
# on a node (ssh, or: kubectl debug node/nuc-01 --profile=sysadmin --image=<node-manager image> -it -- chroot /host sh)
ethtool -i eno1 | grep driver
ethtool -k eno1 | grep -E "^(tcp-segmentation|generic-segmentation|generic-receive)-offload:"
ethtool --show-eee eno1 | grep "EEE status"
ls -l /oem/99_e1000e_offload_fix.yaml
dmesg | grep -c "Hardware Unit Hang"
```

## Recovering a hung node
The NIC doesn't recover by itself: power-cycle the node from its KVM
(nuc-0x-kvm). Keep at least two of nuc-01..03 up (etcd quorum).
