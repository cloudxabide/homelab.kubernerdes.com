# Network Devices

Port maps for every network device in the lab. Fill in the blanks when cabling changes, then update `Diagram/inventory.yaml` and run `Diagram/render.sh`.

- **Confirmed** entries come from the Sophos and Cisco UIs, photos of the switches, and the BIND/dhcpd configs in `Files/nuc-00/`. All were read on 2026-11-21.
- **Blank** = not known yet. `?` = partly known.
- **Speed** = negotiated link speed (what the port LEDs or `ethtool` show), not what the device supports.
- **VLANs:** `U` = untagged, `T` = tagged.

### How to fill this in

Each switch has one row per port: **Port | Hostname | Interface | VLAN**, plus Speed if you know it.

| Column | Use | Examples |
|:-------|:----|:---------|
| Hostname | as in DNS; for a switch-to-switch cable, the other switch and its port | `nuc-04`, `nuc-04-kvm`, `nuc-00`, `MikroTik:16`, `Cisco:GE1` |
| Interface | the host's interface name (see "Host interfaces" below); `uplink` for a switch-to-switch cable | `enp86s0`, `eno1`, `enp0s13f0u1`, `eth0` |
| VLAN | what is on that cable: the number for untagged, `T` after it for tagged | `12`, `128T`, `12 + 128T` |
| Speed (optional) | negotiated speed, from the port LEDs or `ethtool <if> \| grep Speed` | `100M`, `1G`, `2.5G`, `10G` |

Example rows for a NUC switch after re-cabling:

| Port | Hostname | Interface | VLAN | Speed |
|:-----|:---------|:----------|:-----|:-----:|
| 1 | Cisco:GE1 | uplink | 12 | 1G |
| 2 | nuc-00 | | 12 | 2.5G |
| 3 | nuc-04 | enp86s0 | 12 | 2.5G |
| 4 | nuc-04 | enp0s13f0u1 | 128T | 1G |
| 5 | nuc-04-kvm | eth0 | 12 | 100M |
| 6 | | | | |

Shorthand is fine too: send me lines like `NICGIGA 3 = nuc-04 enp86s0 vlan 12` and I'll fill in the tables.

## VLANs / zones

| VLAN | Name | Subnet | Sophos port | Notes |
|:----:|:-----|:-------|:-----------:|:------|
| — | WAN | static /29 | Port2 | Comporium, bridged |
| 192 | LAN | 192.168.0.0/22 | Port1 (U) | home network |
| 172 | IoT | 172.16.0.0/23 | Port1 (T) | |
| 12 | LAB (DMZ) | 10.10.12.0/22 | Port3 | .12 homelab · .13 enclave · .14 community · .15 prime |
| 10 | DMZ-2 | 10.0.0.0/22 | Port4 | vacant; NUCs move here at times |
| 128 | STORAGE | 192.168.128.0/24 | — | Longhorn replication, USB-C NICs only; never reaches the Cisco |
| — | AWS VPC | 172.18.0.0/16 | — | via Tailscale (ts-onprem ⇄ tailscale-01) |

---

## Switches

| Switch | Model | Role | Ports | Managed | Mgmt IP / DNS | OS / firmware | Location | Uplink | Status |
|:-------|:------|:-----|:------|:--------|:--------------|:--------------|:---------|:-------|:-------|
| cisco-sg300-28 | Cisco SG300-28 | core | 24× 1G RJ45 + 4× 1G combo (RJ45/SFP) | yes (L2, VLANs, LAG) | 10.10.12.2 · cisco-sg300-28.homelab | | | Sophos Port1 / Port3 / Port4 (GE24 / GE28 / GE21) | in use |
| NICGIGA | NICGIGA S25-1602 | NUC switch (gen13 today) | 16× 2.5G RJ45 + 2× 10G SFP+ | no | none | — | gen13 10" rack | Cisco GE1 (1G) | in use |
| mikrotik-switch | MikroTik CSS318-16G-2S+in | NUC switch (gen10 today) | 16× 1G RJ45 + 2× 10G SFP+ | SwOS, used as a plain switch | 10.10.12.3 · mikrotik-switch.homelab | SwOS ___ | gen10 10" rack | NICGIGA port 16 (1G copper) | in use |
| TL-SX1008 | TP-Link TL-SX1008 | spare (storage switch?) | 8× 10GBASE-T (100M–10G) | no | none | — | | | not in use |
| office | | behind Cisco GE11 (VLAN 10) | | | | | office | Cisco GE11 | ? |
| main floor | | behind Cisco GE25 (trunk 192U, 10T, 12T, 172T) | | | | | main floor | Cisco GE25 | ? |
| enclave | | behind Cisco GE26 (VLAN 12) | | | | | | Cisco GE26 | ? |

Fill in a row's blanks if it's a switch. If it's something else (a single host, an AP), say what it is and I'll move it to the right table.

Other network gear:

| Device | Model | Role | Mgmt IP / DNS | OS / firmware | Connected to |
|:-------|:------|:-----|:--------------|:--------------|:-------------|
| sophos-xgs88 | Sophos XGS 88 | firewall / router for all zones | 10.10.12.1 · sophos-xgs88.homelab | SFOS ___ | see the Sophos section below |
| unifi-ap-east | UniFi ___ | Wi-Fi | | | Cisco GE23 (trunk) |
| unifi-ap-west | UniFi ___ | Wi-Fi | | | |
| Hue bridge | Philips Hue Bridge | IoT hub | 172.16.___ | | Cisco GE22 (VLAN 172) |
| ts-onprem | VM on nuc-00 | Tailscale subnet router (10.10.12.0/22 ⇄ AWS 172.18.0.0/16) | 10.10.12.14 · ts-onprem.homelab | | nuc-00 (bridged) |

---

## Sophos XGS 88: firewall

`10.10.12.1` · `sophos-xgs88.homelab.kubernerdes.com` · SFOS version: ________

| Port | Zone | Interface IP | Speed | Connected to | Notes |
|:-----|:-----|:-------------|:-----:|:-------------|:------|
| Port1 | LAN | 192.168.0.1/22 | 1G | Cisco GE24 | + VLAN 172 (IoT) tagged, 172.16.0.1/23 |
| Port2 | WAN | static /29 | 2.5G | Comporium (bridged) | |
| Port3 | DMZ | 10.10.12.1/22 | 1G | Cisco GE28 | VLAN 12 |
| Port4 | DMZ | 10.0.0.1/22 | 1G | Cisco GE21 | VLAN 10 |

Services in use (DHCP, DNS, IPS, VPN, …): ________

---

## Cisco SG300-28: core switch (L2 managed)

`10.10.12.2` · `cisco-sg300-28.homelab.kubernerdes.com` · firmware: ________

GE25–28 are combo ports (RJ45 or SFP). LAG membership: GE9+10, GE14+15 and GE18+19 show as LAG members. The VLANs on the LAGs themselves (LAG1…LAG8 rows) are not recorded yet.

| Port | Description (on switch) | Mode | VLANs | Connected to | Speed | Notes |
|:-----|:------------------------|:-----|:------|:-------------|:-----:|:------|
| GE1 | enclave-lab-crawlspace | Trunk | 12U | NICGIGA (port ___) | 1G | uplink for the NUC switches |
| GE2 | truenas_192 | Trunk | 192U | truenas | | LAN leg |
| GE3 | | Trunk | 1U | free | | |
| GE4 | | Trunk | 1U | free | | |
| GE5 | | Trunk | 1U | free | | |
| GE6 | | Trunk | 1U | free | | |
| GE7 | | Trunk | 1U | free | | |
| GE8 | | Trunk | 12U | | | unlabeled, VLAN 12 |
| GE9 | truenas-pci1-1 | LAG ___ | LAG VLANs: ___ | truenas | | |
| GE10 | truenas-pci1-2 | LAG ___ | LAG VLANs: ___ | truenas | | |
| GE11 | office_uplink_vlan10 | Trunk | 10U | office | | |
| GE12 | | Trunk | 1U | free | | |
| GE13 | asus-pc-02-eth0 | Trunk | 12U | asus-pc-02 | | |
| GE14 | asus-pc-02-pci1-1 | LAG ___ | LAG VLANs: ___ | asus-pc-02 | | |
| GE15 | asus-pc-02-pci2-1 | LAG ___ | LAG VLANs: ___ | asus-pc-02 | | |
| GE16 | | Trunk | 1U | free | | |
| GE17 | asus-pc-03-eth0 | Trunk | 12U | asus-pc-03 | | |
| GE18 | asus-pc-03-pci1-1 | LAG ___ | LAG VLANs: ___ | asus-pc-03 | | |
| GE19 | asus-pc-03-pci2-1 | LAG ___ | LAG VLANs: ___ | asus-pc-03 | | |
| GE20 | nexus.evil.corp | Access | 192U | nexus | | |
| GE21 | sophos_port4_vlan10 | Access | 10U | Sophos Port4 | 1G | |
| GE22 | hue_vlan172 | Trunk | 172U | Hue bridge | | |
| GE23 | unifi-ap-east | Trunk | 192U, 10T, 12T, 172T | UniFi AP east | | |
| GE24 | sophos_port1_vlan192 | Trunk | 192U, 172T | Sophos Port1 | 1G | |
| GE25 | uplink-main-floor-vlan192 | Trunk | 192U, 10T, 12T, 172T | main floor | | UniFi AP west behind this? ___ |
| GE26 | enclave-uplink | Trunk | 12U | enclave | | |
| GE27 | nuc-farm-uplink | Trunk | 10U | (spare) | | name is stale: NUCs are on VLAN 12 via GE1 |
| GE28 | sophos_port3_vlan12 | Trunk | 12U | Sophos Port3 | 1G | |

---

## NICGIGA S25-1602: NUC switch (unmanaged)

16× 2.5G RJ45 + 2× 10G SFP+ (17–18) · no IP · LEDs: green = 2.5G link, yellow = link/activity

Port 16 ↔ MikroTik port 16 and the empty SFP+ cages are from the photo.

| Port | Hostname | Interface | VLAN | Speed |
|:-----|:---------|:----------|:-----|:-----:|
| 1 |  |  |  |  |
| 2 |  |  |  |  |
| 3 |  |  |  |  |
| 4 |  |  |  |  |
| 5 |  |  |  |  |
| 6 |  |  |  |  |
| 7 |  |  |  |  |
| 8 |  |  |  |  |
| 9 |  |  |  |  |
| 10 |  |  |  |  |
| 11 |  |  |  |  |
| 12 |  |  |  |  |
| 13 |  |  |  |  |
| 14 |  |  |  |  |
| 15 |  |  |  |  |
| 16 | MikroTik:16 | uplink | 12 + 128T | 1G |
| 17 (SFP+) |  |  |  |  |
| 18 (SFP+) |  |  |  |  |

---

## MikroTik CSS318-16G-2S+in: NUC switch

16× 1G RJ45 + 2× 10G SFP+ · `10.10.12.3` · `mikrotik-switch.homelab.kubernerdes.com` · SwOS (used as a plain switch)

Port 16 ↔ NICGIGA port 16 and the empty SFP+ cages are from the photo.

| Port | Hostname | Interface | VLAN | Speed |
|:-----|:---------|:----------|:-----|:-----:|
| 1 |  |  |  |  |
| 2 |  |  |  |  |
| 3 |  |  |  |  |
| 4 |  |  |  |  |
| 5 |  |  |  |  |
| 6 |  |  |  |  |
| 7 |  |  |  |  |
| 8 |  |  |  |  |
| 9 |  |  |  |  |
| 10 |  |  |  |  |
| 11 |  |  |  |  |
| 12 |  |  |  |  |
| 13 |  |  |  |  |
| 14 |  |  |  |  |
| 15 |  |  |  |  |
| 16 | NICGIGA:16 | uplink | 12 + 128T | 1G |
| SFP+1 |  |  |  |  |
| SFP+2 |  |  |  |  |

---

## TP-Link TL-SX1008: spare (not in use)

8× 10GBASE-T RJ45, multi-gig (100M / 1G / 2.5G / 5G / 10G) · unmanaged

| Port | Hostname | Interface | VLAN | Speed |
|:-----|:---------|:----------|:-----|:-----:|
| 1 |  |  |  |  |
| 2 |  |  |  |  |
| 3 |  |  |  |  |
| 4 |  |  |  |  |
| 5 |  |  |  |  |
| 6 |  |  |  |  |
| 7 |  |  |  |  |
| 8 |  |  |  |  |

---

## Host interfaces (reference)

Interface names for the Interface column, from `Scripts/env.d/*.sh` and `Foo/NIC_issue.md`. Where each one plugs in goes in the switch tables above. A USB NIC's interface name depends on the USB port it's plugged into, so keep each adapter in the same port.

| Host | Role | NIC | Interface | IP |
| :----- | :----- | :---- | :---------- | :--- |
| nuc-00 | admin host | onboard Intel i226-V (2.5G) |  | 10.10.12.10 |
| nuc-01 | Harvester (gen10) | onboard Intel I219-V (1G), mgmt | eno1 | 10.10.15.101 |
| nuc-01 |  | USB-C Satechi (2.5G), storage | enp0s20f0u4 | 192.168.128.x |
| nuc-02 | Harvester (gen10) | onboard Intel I219-V (1G), mgmt | eno1 | 10.10.15.102 |
| nuc-02 |  | USB-C Satechi (2.5G), storage | enp0s20f0u4 | 192.168.128.x |
| nuc-03 | Harvester (gen10) | onboard Intel I219-V (1G), mgmt | eno1 | 10.10.15.103 |
| nuc-03 |  | USB-C Satechi (2.5G), storage | enp0s20f0u4 | 192.168.128.x |
| nuc-04 | Harvester (gen13) | onboard Intel i226-V (2.5G), mgmt | enp86s0 | 10.10.15.104 |
| nuc-04 |  | USB-C ___ (1G?), storage | enp0s13f0u1 | 192.168.128.x |
| nuc-05 | Harvester (gen13) | onboard Intel i226-V (2.5G), mgmt | enp86s0 | 10.10.15.105 |
| nuc-05 |  | USB-C ___ (1G?), storage | enp0s13f0u1 | 192.168.128.x |
| nuc-06 | Harvester (gen13) | onboard Intel i226-V (2.5G), mgmt | enp86s0 | 10.10.15.106 |
| nuc-06 |  | USB-C ___ (1G?), storage | enp0s13f0u1 | 192.168.128.x |

## Out-of-band (Sipeed NanoKVM)

| KVM | IP | MAC | Attached to |
| :---- | :--- | :---- | :------------ |
| nuc-01-kvm | 10.10.12.111 | 48:da:35:6f:72:b3 | nuc-01 |
| nuc-02-kvm | 10.10.12.112 | 48:da:35:6f:3e:c2 | nuc-02 |
| nuc-03-kvm | 10.10.12.113 | 48:da:35:6f:e4:4f | nuc-03 |
| nuc-04-kvm | 10.10.12.114 | 48:da:35:6f:a9:8c | nuc-04 |
| nuc-05-kvm | 10.10.12.115 | 48:da:35:6f:06:38 | nuc-05 |
| nuc-06-kvm | 10.10.12.116 | 48:da:35:6f:9e:17 | nuc-06 |

The MACs come from `Files/nuc-00/etc/dhcpd.d/dhcpd-kvms.conf`. Check that each KVM is still attached to the NUC its name says after re-racking.

## Wireless

| AP | Model | Switch | Port | Notes |
|:---|:------|:-------|:----:|:------|
| unifi-ap-east | UniFi ___ | Cisco | GE23 | trunk: 192U, 10T, 12T, 172T |
| unifi-ap-west | UniFi ___ | | | |
