# Hardware Inventory

Physical hardware, bill of materials, and network switch layout.

## Hardware Catalog

One catalog for all hardware, whatever ENVIRONMENT it is built as. The six NUCs (nuc-01 … nuc-06) form a single Harvester cluster. ENVIRONMENT (community | prime | enclave) only selects the /24 and the software source they are rebuilt with, and only one environment runs at a time.

Power figures are whole-system estimates in watts (PSU losses not included). Rate: $0.14/kWh, so monthly cost = W × 730 h × $0.14 / 1000.

### Systems

| System | Role | Model | CPU | Cores / Threads | RAM (GB) | Disks | Mgmt NIC | Idle (W) | Avg (W) | Max (W) |
|:-------|:-----|:------|:----|:---------------:|:--------:|:------|:---------|:--------:|:-------:|:-------:|
| nuc-00 | Admin host (BIND, dhcpd, PXE, Vault, libvirt VMs) | NUC13ANHi3 | i3-1315U | 6C / 8T | 32 | 512 GB NVMe | 2.5G | 6 | 20 | 54 |
| nuc-01 | Harvester · control-plane (gen10) | NUC10i7FNH | i7-10710U | 6C / 12T | 64 | 2 TB SSD + 1 TB NVMe | 1G | 7 | 28 | 65 |
| nuc-02 | Harvester · control-plane (gen10) | NUC10i7FNH | i7-10710U | 6C / 12T | 64 | 2 TB SSD + 1 TB NVMe | 1G | 7 | 28 | 65 |
| nuc-03 | Harvester · control-plane (gen10) | NUC10i7FNH | i7-10710U | 6C / 12T | 64 | 2 TB SSD + 1 TB NVMe | 1G | 7 | 28 | 65 |
| nuc-04 | Harvester · worker (gen13) | NUC13ANHi7 | i7-1360P | 12C / 16T | 64 | 2 TB SSD + 1 TB NVMe | 2.5G | 10 | 35 | 64 |
| nuc-05 | Harvester · worker (gen13) | NUC13ANHi7 | i7-1360P | 12C / 16T | 64 | 2 TB SSD + 1 TB NVMe | 2.5G | 10 | 35 | 64 |
| nuc-06 | Harvester · worker (gen13) | NUC13ANHi7 | i7-1360P | 12C / 16T | 64 | 2 TB SSD + 1 TB NVMe | 2.5G | 10 | 35 | 64 |
| nuc-99 | No role yet (admin host if the gen10s become their own cluster) | NUC10 (gen10) | ? | ? | ? | ? | 1G | 7 | 10 | 65 |
| truenas | NAS / NFS, backups (TrueNAS SCALE) | ASUS X99-PRO/USB 3.1 | Xeon E5-2630 v3 | 8C / 16T | 94 | 1 TB SSD (OS) + 3× 4 TB HDD (pool) | 1G + 2× 1G LAG | 80 | 120 | 200 |
| spark-e | GPU / AI host (optional) | NVIDIA DGX Spark | GB10 Grace Blackwell | 20C | 128 (unified) | ? | 2.5G ? | 40 ¹ | 100 ¹ | 240 ¹ |
| **Systems total** | | | | | | | | **184** | **439** | **946** |

Each Harvester NUC also has a USB-C NIC for the storage network (VLAN 128): Satechi 2.5G on the gen10s, an unknown 1G adapter on the gen13s. See `Network_Devices.md`.

¹ DGX Spark: max is the 240 W power adapter rating; idle and average are guesses until measured.

### Network and out-of-band

| Device | Role | Model | Ports | Idle (W) | Avg (W) | Max (W) |
|:-------|:-----|:------|:------|:--------:|:-------:|:-------:|
| sophos-xgs88 | Firewall / router for all zones | Sophos XGS 88 | 4 used (WAN 2.5G, 3× 1G) | 10 | 13 | 20 |
| cisco-sg300-28 | Core switch (L2, VLANs, LAG) | Cisco SG300-28 | 24× 1G + 4× 1G combo | 15 | 18 | 25 |
| NICGIGA | 2.5G switch: gen13 NUCs, nuc-00, DGX Spark | NICGIGA S25-1602 | 16× 2.5G + 2× 10G SFP+ | 10 | 14 | 20 |
| mikrotik-switch | 1G switch: gen10 NUCs, nuc-99, NanoKVMs | MikroTik CSS318-16G-2S+in | 16× 1G + 2× 10G SFP+ | 6 | 8 | 13 |
| nuc-0[1-6]-kvm | Out-of-band console, one per Harvester NUC (6 units) | Sipeed NanoKVM | 1× 100M each | 6 | 9 | 12 |
| **Network total** | | | | **47** | **62** | **90** |

Network figures are estimates from typical datasheet values, not measured. Home network gear (UniFi APs, Hue bridge) is not included.

### Power summary (in service)

| Group | Idle (W) | Idle $/mo | Avg (W) | Avg $/mo | Max (W) | Max $/mo |
|:------|:--------:|:---------:|:-------:|:--------:|:-------:|:--------:|
| Harvester cluster (nuc-01 … nuc-06) | 51 | $5.21 | 189 | $19.32 | 387 | $39.55 |
| Other systems (nuc-00, nuc-99, truenas, spark-e) | 133 | $13.59 | 250 | $25.55 | 559 | $57.13 |
| Network and out-of-band | 47 | $4.80 | 62 | $6.34 | 90 | $9.20 |
| **Grand total** | **231** | **$23.61** | **501** | **$51.20** | **1,036** | **$105.88** |

### Spares / unused

Hardware on hand but not in service. It is not counted in the totals above.

| System | Role | Model | CPU | Cores / Threads | RAM (GB) | Disks | Idle (W) | Avg (W) | Max (W) |
|:-------|:-----|:------|:----|:---------------:|:--------:|:------|:--------:|:-------:|:-------:|
| asus-01 | Spare (ATX desktop) | ASUS ? | i9-10850K | 10C / 20T | ? | ? | 65 | 175 | 320 |
| asus-02 | Spare (ATX desktop) · cabled to Cisco GE13-15 | ASUS ? | i9-10850K | 10C / 20T | ? | ? | 65 | 175 | 320 |
| asus-03 | Spare (ATX desktop) · cabled to Cisco GE17-19 | ASUS ? | i9-10850K | 10C / 20T | ? | ? | 65 | 175 | 320 |
| TL-SX1008 | Spare 10G switch (possible storage-network switch) | TP-Link TL-SX1008 | — | 8× 10GBASE-T (100M … 10G), unmanaged | — | — | 10 | 15 | 30 |
| **Spares total (if powered on)** | | | | | | | **205** | **540** | **990** |

If powered on, the spares would add about $20.95/mo at idle, $55.19/mo average and $101.18/mo at max.

## IP Assignments

The supernet is `10.10.12.0/22`. Each environment occupies one `/24`; each reserves `.228-.254` as a dynamic DHCP pool.

| Subnet | Environment | Notes |
|:-------|:------------|:------|
| 10.10.12.0/24 | homelab | Shared infrastructure (DNS, DHCP, admin, NAS) |
| 10.10.13.0/24 | enclave | nuc-01/02/03 Harvester cluster |
| 10.10.14.0/24 | community | nuc-01/02/03 Harvester cluster |
| 10.10.15.0/24 | prime | nuc-01/02/03 Harvester cluster |

Infrastructure IPs — homelab (10.10.12.x), shared across all environments:

| IP | Hostname | Purpose |
|:---|:---------|:--------|
| 10.10.12.1 | gateway | Default gateway / router |
| 10.10.12.8 | nuc-00-01 | DNS primary + DHCP + TFTP (infra VM on nuc-00) |
| 10.10.12.9 | nuc-00-02 | DNS secondary (infra VM on nuc-00) |
| 10.10.12.10 | nuc-00 | Admin host (Apache + KVM) |
| 10.10.12.11 | nas | NAS / NFS storage (TrueNAS Scale) |
| 10.10.12.12 | librenms | Network monitoring (VM, optional) |
| 10.10.12.93 | nuc-00-03 | HAProxy load balancer (infra VM on nuc-00) |
| 10.10.12.193 | nuc-00-03-vip | HAProxy Keepalived VIP |

Per-environment IPs (last octet identical across all environments, prefix differs):

| Last Octet | enclave (10.10.13.x) | community (10.10.14.x) | prime (10.10.15.x) | Purpose |
|:----------:|:---------------------|:-----------------------|:---------------------|:--------|
| .101 | nuc-01 | nuc-01 | nuc-01 | Harvester node 1 |
| .102 | nuc-02 | nuc-02 | nuc-02 | Harvester node 2 |
| .103 | nuc-03 | nuc-03 | nuc-03 | Harvester node 3 |
| .111-.113 | nuc-0x-kvm | nuc-0x-kvm | nuc-0x-kvm | KVM / IPMI interfaces |
| .210 | rancher-VIP | rancher-VIP | rancher-VIP | Rancher Manager cluster VIP |
| .211-.213 | rancher-11/12/13 | rancher-21/22/23 | rancher-01/02/03 | Rancher Manager nodes |
| .220 | observability-VIP | observability-VIP | observability-VIP | Observability cluster VIP |
| .221-.223 | observability-11/12/13 | observability-21/22/23 | observability-01/02/03 | Observability nodes |
| .230 | apps-VIP | apps-VIP | apps-VIP | Applications cluster VIP |
| — | apps-* (DHCP) | apps-* (DHCP) | apps-* (DHCP) | Applications cluster nodes (Harvester DHCP, no fixed IPs) |
| .251 | — | — | spark-e | Optional hardware |
| .228-.254 | dynamic pool | dynamic pool | dynamic pool | DHCP dynamic range |

Wildcard DNS: `*.apps.${ENVIRONMENT}.kubernerdes.com` → `${IP_PREFIX}.230`

## Bill of Materials

| Total | Unit Cost | Qty | Item |
|------:|----------:|:---:|:-----|
| $350 | $350 | 1 | Intel NUC NUC13ANHi3 (admin host) |
| $2,700 | $900 | 3 | Intel NUC NUC13ANHi7 (community Harvester nodes) |
| $304 | $76 | 4 | Chicony A17-120P2A 20V 6A 120W PSU (5.5mm–2.5mm) |
| $36 | $12 | 3 | 1GB USB-C network adapter |
| $110 | $110 | 1 | Portable monitor (ViewSonic VA1655) |
| $20 | $10 | 2 | Power strip |
| $7 | $7 | 1 | Mouse |
| $20 | $10 | 20 | 28 AWG Cat6 cables (10-pack) |
| **$4,547** | | | **Estimated total (prime+community; enclave TBD)** |

## Network Switch Layout

16-port unmanaged switch port assignments (prime + community shown; enclave ports TBD).

| Port | Host | Notes | Port | Host | Notes |
|:----:|:-----|:------|:----:|:-----|:------|
| 1 | nuc-00 | Admin host | 9 | nuc-02-kvm | KVM secondary NIC |
| 2 | nuc-01 | prime Harvester node 1 | 10 | nuc-03-kvm | KVM secondary NIC |
| 3 | nuc-02 | prime Harvester node 2 | 11 | nuc-01 | community Harvester node 1 |
| 4 | nuc-03 | prime Harvester node 3 | 12 | nuc-02 | community Harvester node 2 |
| 5 | nuc-01-vms | VM traffic NIC | 13 | nuc-03 | community Harvester node 3 |
| 6 | nuc-02-vms | VM traffic NIC | 14 | | |
| 7 | nuc-03-vms | VM traffic NIC | 15 | spark-e | Optional |
| 8 | nuc-01-kvm | KVM secondary NIC | 16 | uplink | Internet |

## MAC Addresses

MAC addresses are set per environment in `Scripts/env.d/${ENVIRONMENT}.sh`.

| Host | MAC | Environment |
|:-----|:----|:------------|
| nuc-01 | 88:ae:dd:0b:90:70 | prime (Gen10) |
| nuc-02 | 1c:69:7a:ab:23:50 | prime (Gen10) |
| nuc-03 | 88:ae:dd:0b:af:9c | prime (Gen10) |
| nuc-01 | TBD | enclave |
| nuc-02 | TBD | enclave |
| nuc-03 | TBD | enclave |
| nuc-01 | 48:21:0b:65:ce:e5 | community (Gen13) |
| nuc-02 | 48:21:0b:65:c2:c7 | community (Gen13) |
| nuc-03 | 48:21:0b:5d:7a:e6 | community (Gen13) |
