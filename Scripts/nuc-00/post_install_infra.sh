#!/bin/bash
set -euo pipefail

# post_install_infra.sh — Install and configure nuc-00's infra services:
# DNS (BIND), DHCP (ISC dhcpd), and TFTP/PXE-HTTP (Apache).
#
# Run as the admin-node user (mansible) on nuc-00 after Apache is already up
# (see the general nuc-00 bootstrap for SSH key / sudo / Apache / KVM setup).
# Intended for cut-and-paste or direct execution from within a checkout of
# this repo on nuc-00 — it copies config from Files/nuc-00/ in THIS repo
# using paths relative to this script, so no network fetch is required.
#
# Historically these services ran split across two infra VMs hosted on
# nuc-00 via libvirt: nuc-00-01 (DNS primary + DHCP + TFTP) and nuc-00-02
# (DNS secondary). Both VMs are retired as of this repo — nuc-00 now runs
# everything directly on the admin host itself. See PLAN.md.
#
# What this script does NOT do:
#   - Render/deploy Files/nuc-00/srv/www/htdocs/harvester/harvester/ipxe-menu.tmpl
#     or the Harvester node config-*.yaml.tmpl files. Those are per-ENVIRONMENT
#     (envsubst against Scripts/env.sh + env.d/${ENVIRONMENT}.sh) and belong to
#     the Day 1 Harvester build, not this infra bootstrap.
#   - Create libvirt VMs — there are none left to create.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FILES_DIR="${REPO_ROOT}/Files/nuc-00"

if [[ "$(hostname -s)" != "nuc-00" ]]; then
  echo "WARNING: this host is $(hostname -s), not nuc-00. Continuing anyway." >&2
fi

MYUSER=$(whoami)
echo "${MYUSER} ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/${MYUSER}-nopasswd-all >/dev/null

# ---------------------------------------------------------------------------
# DNS + DHCP pattern (BIND + ISC dhcpd) + TFTP + Apache (PXE-HTTP)
# Apache may already be installed as part of the general nuc-00 bootstrap —
# these installs are idempotent.
# ---------------------------------------------------------------------------
sudo zypper --non-interactive install -t pattern dhcp_dns_server
sudo zypper --non-interactive install bind-utils tftp apache2 apache2-mod_php8

sudo systemctl enable apache2 --now

# ---------------------------------------------------------------------------
# TFTP — serves ipxe.efi for the initial UEFI PXE handoff
#
# Do NOT fetch this from https://boot.netboot.xyz/ipxe/netboot.xyz.efi — that
# build does not re-DHCP with User-Class "iPXE" after loading, so it never
# picks up the HTTP filename from the dhcpd host-block conditional. It falls
# back to looking for autoexec.ipxe over TFTP instead, which silently breaks
# the PXE menu handoff (see git history for the incident this came from).
#
# Files/nuc-00/srv/tftpboot/ipxe.efi is a known-good build (verified against
# this repo's dhcpd.conf host-block iPXE re-chain) with unknown upstream
# provenance — treat replacing it as high-risk and re-verify PXE end-to-end
# if it's ever swapped.
# ---------------------------------------------------------------------------
sudo mkdir -p /srv/tftpboot
sudo cp "${FILES_DIR}/srv/tftpboot/ipxe.efi" /srv/tftpboot/ipxe.efi

# ---------------------------------------------------------------------------
# BIND configuration — copied from this repo's Files/nuc-00/ tree
# ---------------------------------------------------------------------------
sudo cp /etc/named.conf "/etc/named.conf.$(date +%F)" 2>/dev/null || true
sudo cp "${FILES_DIR}/etc/named.conf" /etc/named.conf

sudo mkdir -p /var/lib/named/master /var/lib/named/slave /var/lib/named/dyn
for ZONE_FILE in "${FILES_DIR}"/var/lib/named/master/*; do
  sudo cp "${ZONE_FILE}" "/var/lib/named/master/$(basename "${ZONE_FILE}")"
done
sudo chown -R root:named /var/lib/named/master

sudo named-checkconf /etc/named.conf
for ZONE_FILE in /var/lib/named/master/db.*.kubernerdes.com /var/lib/named/master/db-*.in-addr.arpa; do
  ZONE_NAME=$(basename "${ZONE_FILE}" | sed -e 's/^db\.//' -e 's/^db-//')
  sudo named-checkzone "${ZONE_NAME}" "${ZONE_FILE}"
done

sudo systemctl enable named --now
sudo systemctl status named --no-pager
host -l homelab.kubernerdes.com localhost || true

# ---------------------------------------------------------------------------
# DHCP configuration — copied from this repo's Files/nuc-00/ tree
# ---------------------------------------------------------------------------
sudo cp /etc/dhcpd.conf "/etc/dhcpd.conf.$(date +%F)" 2>/dev/null || true
sudo cp "${FILES_DIR}/etc/dhcpd.conf" /etc/dhcpd.conf
sudo mkdir -p /etc/dhcpd.d/
sudo cp "${FILES_DIR}"/etc/dhcpd.d/*.conf /etc/dhcpd.d/

sudo dhcpd -t -cf /etc/dhcpd.conf

PRIMARY_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
sudo sed -i -e "s/DHCPD_INTERFACE=\"ANY\"/DHCPD_INTERFACE=\"${PRIMARY_IFACE}\"/g" /etc/sysconfig/dhcpd

sudo mkdir -p /etc/systemd/system/dhcpd.service.d
printf '[Unit]\nRequires=network-online.target\nAfter=network-online.target\n' \
  | sudo tee /etc/systemd/system/dhcpd.service.d/override.conf >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable dhcpd --now
sudo systemctl status dhcpd --no-pager

# ---------------------------------------------------------------------------
# Firewall
# ---------------------------------------------------------------------------
for PORT in 53 80 443; do sudo firewall-cmd --permanent --zone=public --add-port=${PORT}/tcp; done
for PORT in 53 67 68 69 4011; do sudo firewall-cmd --permanent --zone=public --add-port=${PORT}/udp; done
for SVC in http https dns dhcp tftp; do sudo firewall-cmd --permanent --zone=public --add-service=${SVC}; done
sudo firewall-cmd --reload
sudo firewall-cmd --list-all

echo
echo "==> nuc-00 infra services (DNS/DHCP/TFTP/PXE-HTTP) installed."
echo "    Next: render and deploy Files/nuc-00/srv/www/htdocs/harvester/harvester/ipxe-menu.tmpl"
echo "    per environment as part of the Day 1 Harvester build."
echo

exit 0
