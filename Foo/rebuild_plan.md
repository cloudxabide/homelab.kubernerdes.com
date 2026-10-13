OK - I am going to "start over" and rebuild the cluster.
  Can you reframe what I need to do "from scratch" (i.e. what things I have to do, what things to avoid, etc..)

  I think mgmt and VMs will be on the onboard Intel 1Gbe NIC
  storage will be on the secondary/USB NIC

  Ran 1 shell command

Here's the rebuild plan. Order matters: the storage network, VM network and storage class all need to exist before you create any VM or volume. Setting them up later means stopping everything, which is the mess you're in now.

The target design

┌───────────────────────────┬─────────────────────────────────────────────┬────────────────────────────────────────────────┐
│          Traffic          │                     NIC                     │                Harvester object                │
├───────────────────────────┼─────────────────────────────────────────────┼────────────────────────────────────────────────┤
│ Harvester management + VM │ Onboard Intel (eno1 on nuc-01–03, enp86s0   │ Built-in mgmt cluster network, with an         │
│  traffic                  │ on nuc-04–06)                               │ untagged VM network on it                      │
├───────────────────────────┼─────────────────────────────────────────────┼────────────────────────────────────────────────┤
│ Longhorn replication      │ USB 1 GbE (enp0s20f0u4 on nuc-01–03,        │ New storage cluster network + storage-network  │
│                           │ enp0s13f0u1 on nuc-04–06)                   │ setting                                        │
└───────────────────────────┴─────────────────────────────────────────────┴────────────────────────────────────────────────┘

Running VMs on the built-in mgmt network means the VM network exists on all 6 nodes, so Rancher VMs can be scheduled anywhere. The current split is what forced all three onto nuc-02/03.

Day 0: before you install anything

1. Cabling. Put each USB adapter in the same USB port on every NUC of the same model. Linux names the interface after the port (...u4, ...u1), so moving an adapter renames it and breaks the VLAN config.
2. Check the onboard NIC drivers. Run ethtool -i <nic> on each model. eno1 on the 01–03 nodes is most likely e1000e (I219), which is what your hang workaround is for. enp86s0 on 04–06 is probably a different driver (an I226 uses igc), so the e1000e fix may not apply there. Don't assume one fix covers both.
3. Fix the heredoc in Foo/NIC_issue.md. cat EOF < /oem/... reads from the file instead of writing to it. It should be:
cat > /oem/99_nic_fix.yaml <<'EOF'
...
EOF
   Better still, put the workaround in the Harvester install config (os.write_files or the /oem stage) so it's there from first boot instead of being patched in afterwards.
4. Harvester install config. Include:
   - os.ssh_authorized_keys with your key. I couldn't SSH into the NUCs this time, which made troubleshooting much harder.
   - NTP and DNS settings.
   - Management interface = the onboard NIC only.
5. Disks. Install the OS on the SATA SSD and give Longhorn the NVMe as its data disk. etcd cares most about fsync latency, so the faster disk should hold the VM volumes.
6. DHCP and DNS on nuc-00:
   - Reservations for nuc-01 to nuc-06 (onboard MACs).
   - Reservations for rancher-01 to rancher-03. Pick fixed MACs now (for example 52:54:00:14:00:31) and set the same MACs in the VM specs later, so the VMs get 10.10.14.31–33 as env.sh expects instead of random 10.10.12.2xx addresses.
   - DNS: rancher → 10.10.14.30, and decide what provides that VIP (see step 13).
7. Clean up known_hosts. Delete the old host keys for all NUC and VM IPs (ssh-keygen -R) so a reinstall doesn't block SSH.

Day 1: build in this order

Harvester

8. Install nuc-01, then join nuc-02 and nuc-03 before nuc-04 to nuc-06. Harvester promotes the first three nodes to control plane, and you want those to be 01–03.
9. Check that every node shows Ready, that you can SSH to each one, and that the NIC workaround is applied: ethtool -k eno1 should show TSO, GSO and GRO off.

Gate: create no VMs, volumes or monitoring add-on until step 12 is finished.

10. Storage network. Create a storage cluster network with two VLAN configs, because the USB NIC names differ between the two node groups:
    - One for nuc-01–03 using enp0s20f0u4.
    - One for nuc-04–06 using enp0s13f0u1. Select these nodes by hostname, not by role label: the role labels can change when nodes are promoted.

    Then set the storage network:
{"vlan":100,"clusterNetwork":"storage","range":"192.168.100.0/24"}
    Do this now, while it's cheap: with no VMs or volumes yet, there's nothing to stop first.

    Then verify. Every Longhorn instance-manager pod should have an lhnet1 interface with a 192.168.100.x address, and the Longhorn pods should be Ready. If they aren't, your unmanaged switch is probably dropping VLAN-tagged frames. Find that out now rather than after you have data. If that happens, plug the USB adapters into a separate cheap switch.
11. VM network. Create vmnet-mgmt on the built-in mgmt cluster network, untagged.
12. Storage classes.
    - harvester-longhorn (default): fine for general VMs. You could lower it to 2 replicas.
    - harvester-longhorn-local-1r: numberOfReplicas: "1", dataLocality: best-effort (Harvester's webhook rejects strict-local). Pin the VMs so the single replica stays local. This one is for the Rancher VMs. etcd already keeps 3 copies of the data, so Longhorn copying it 3 more times over the network is pure overhead.

    Watch out for VM images: a root disk created from an image uses the image's storage class (that's why your old disks were on lh-1bf6e526… with 3 replicas). When you upload the SLES 16 image for the Rancher VMs, select harvester-longhorn-local-1r. You may need a second copy of the image for general VMs that use the default class.

Rancher Manager VMs

13. Create rancher-01, rancher-02 and rancher-03:
    - One per control-plane node: pin rancher-01/02/03 to nuc-01/02/03 (Node Scheduling → run on specific node) so those nodes do useful work. Harvester's OS/etcd is on the SATA SSD and the VM disks are on the NVMe, so they don't share a disk; pinning keeps each VM's single best-effort replica local. Don't take two of nuc-01–03 down at once: that costs quorum for both Harvester and Rancher.
    - 4 vCPU, and 16 GB RAM if you can spare it (they had 8 GB).
    - The fixed MACs from step 6, on vmnet-mgmt.
    - Decide on the VIP explicitly. Last time 10.10.14.30 answered, but nothing in your repo creates it. Either deploy kube-vip in ARP mode from your scripts, or skip the VIP and point the rancher DNS name at all three node IPs. Whichever you pick, add the VIP and hostname as tls-san entries in the RKE2 config.
14. Benchmark the disk before installing RKE2. In one VM, run the standard etcd fio test:
fio --rw=write --ioengine=sync --fdatasync=1 --directory=/var/lib --size=22m --bs=2300 --name=etcd
    The 99th-percentile fdatasync should be under about 10 ms. If it's above 1 s, as your logs showed last time, stop and fix storage first.
15. Run 09_install_RKE2_for_rancher_manager.sh and 10_install_rancher_manager.sh, then confirm that ~/.kube/community-rancher.kubeconfig exists and points at the VIP. Afterwards, grep the etcd logs for slow fdatasync; you want zero hits.
16. Only after all this, enable the rancher-monitoring add-on and deploy the apps cluster and observability.

Things to avoid

- Splitting VM networks by node role, which limits where VMs can run.
- Putting two etcd members (Rancher VMs) on the same Harvester host.
- Using 3-replica, remote Longhorn volumes for etcd.
- Enabling add-ons or creating volumes before the storage network is configured.
- Relying on whatever the DHCP pool hands out for infrastructure VMs.
- Moving the Rancher VMs casually. Live migration works with best-effort, but the disk runs over the storage network until Longhorn rebuilds a local replica; migrate one VM at a time.
- Assuming the USB link is fast. It's still 1 GbE and only keeps storage traffic off the management NIC. The real performance gain comes from data locality.

Do you want me to put this in the repo as DeepDive/Rebuild_From_Scratch.md, along with the VLAN config, storage network and storage class YAML in Files/?

✻ Crunched for 1m 11s · done 10:42 AM

※ recap: You're rebuilding the community Harvester and Rancher cluster from scratch, with management and VM traffic on the onboard NIC and storage on the USB NIC, and I've written the step-by-step plan. Next, tell me whether to save it in the repo as `DeepDive/Rebuild_From_Scratch.md` with the YAML files. (disable recaps in /config)

