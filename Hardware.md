# Hardware Inventory

Physical hardware, bill of materials, and network switch layout.

## Systems

| System | Purpose | Environment | Model | CPU | Cores | RAM (GB) | Disk0 (SSD GB) | Disk1 (NVMe GB) |
|:-------|:--------|:------------|:------|:----|------:|:--------:|---------------:|----------------:|
| nuc-00 | Admin Host | (all) | NUC13ANHi3 | i3-1315U | 6 | 32 | — | 512 |
| nas | NAS / NFS storage | (all) | ASUS X99-PRO/USB 3.1 | Xeon E5-2630 v3 | 8 | 94 | 1000 | — |
| nuc-01 | Harvester node 1 | prime | NUC10i7FNH | i7-10710U | 12 | 64 | 1843 | 932 |
| nuc-02 | Harvester node 2 | prime | NUC10i7FNH | i7-10710U | 12 | 64 | 1843 | 932 |
| nuc-03 | Harvester node 3 | prime | NUC10i7FNH | i7-10710U | 12 | 64 | 1843 | 932 |
| nuc-01 | Harvester node 1 | enclave | ROG STRIX Z490-E | i9-285K | 24 | TBD | TBD | TBD |
| nuc-02 | Harvester node 2 | enclave | ROG STRIX Z490-E | i9-285K | 24 | TBD | TBD | TBD |
| nuc-03 | Harvester node 3 | enclave | ROG STRIX Z490-E | i9-285K | 24 | TBD | TBD | TBD |
| nuc-01 | Harvester node 1 | community | NUC13ANHi7 | i7-1360P | 16 | 64 | 1843 | 932 |
| nuc-02 | Harvester node 2 | community | NUC13ANHi7 | i7-1360P | 16 | 64 | 1843 | 932 |
| nuc-03 | Harvester node 3 | community | NUC13ANHi7 | i7-1360P | 16 | 64 | 1843 | 932 |
¹ nas storage: 1 × 1TB SSD (OS), 3 × 4TB HDD (NAS pool, TrueNAS Scale); NFS share TBD

## Power Consumption (Estimated)

enclave nuc-01/02/03 are full ATX desktop systems; all other nodes are NUC form factor. Values are whole-system estimates (PSU losses not included).

**Admin**

| System | CPU | Idle (W) | Average (W) | Max (W) |
|:-------|:----|:--------:|:-----------:|:-------:|
| nuc-00 | i3-1315U | 6 | 20 | 54 |
| nas | Xeon E5-2630 v3 | 80 | 120 | 200 |
| **Total** | | **86** | **140** | **254** |

**prime**

| System | CPU | Idle (W) | Average (W) | Max (W) |
|:-------|:----|:--------:|:-----------:|:-------:|
| nuc-01 | i7-10710U | 7 | 28 | 65 |
| nuc-02 | i7-10710U | 7 | 28 | 65 |
| nuc-03 | i7-10710U | 7 | 28 | 65 |
| **Total** | | **21** | **84** | **195** |

**enclave**

| System | CPU | Idle (W) | Average (W) | Max (W) |
|:-------|:----|:--------:|:-----------:|:-------:|
| nuc-01 | i9-285K | 65 | 175 | 320 |
| nuc-02 | i9-285K | 65 | 175 | 320 |
| nuc-03 | i9-285K | 65 | 175 | 320 |
| **Total** | | **195** | **525** | **960** |

**community**

| System | CPU | Idle (W) | Average (W) | Max (W) |
|:-------|:----|:--------:|:-----------:|:-------:|
| nuc-01 | i7-1360P | 10 | 35 | 64 |
| nuc-02 | i7-1360P | 10 | 35 | 64 |
| nuc-03 | i7-1360P | 10 | 35 | 64 |
| **Total** | | **30** | **105** | **192** |

**Overall Summary**

Rate: $0.14/kWh — monthly cost = Watts × 730 hr × $0.14 / 1000

| Environment | Idle (W) | Idle $/mo | Average (W) | Avg $/mo | Max (W) | Max $/mo |
|:------------|:--------:|:---------:|:-----------:|:--------:|:-------:|:--------:|
| Admin | 86 | $8.79 | 140 | $14.30 | 254 | $25.96 |
| prime | 21 | $2.15 | 84 | $8.58 | 195 | $19.93 |
| enclave | 195 | $19.93 | 525 | $53.66 | 960 | $98.11 |
| community | 30 | $3.07 | 105 | $10.73 | 192 | $19.62 |
| **Grand Total** | **332** | **$33.93** | **854** | **$87.27** | **1,601** | **$163.62** |

Node naming convention: NUC nodes use **nuc-01/02/03** for all environments (distinguished by ENVIRONMENT/domain). Other cluster roles (rancher, observability, apps) follow a digit-prefix scheme: prime=0x, enclave=1x, community=2x (e.g. rancher-01/02/03, rancher-11/12/13, rancher-21/22/23).

All three environments have dedicated hardware and can run simultaneously.

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
| .231-.233 | apps-11/12/13 | apps-21/22/23 | apps-01/02/03 | Applications cluster nodes |
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
