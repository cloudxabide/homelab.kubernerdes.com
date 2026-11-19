#!/bin/bash
set -euo pipefail

# tailscale_install.sh — install or upgrade Tailscale on SL Micro from the
# static tarball. Written to /opt/tailscale/install.sh by cloud-init
# (OpenTofu/aws/tailscale.tf), which runs it on first boot.
#
#   sudo /opt/tailscale/install.sh            # newest stable release
#   sudo /opt/tailscale/install.sh 1.104.7    # pin a version
#
# Why the tarball: SL Micro's /usr is read-only, and installing the package
# needs a transactional-update and a reboot. /opt is writable on SL Micro (RKE2
# installs into /opt/rke2 there too). The systemd unit, the sysctl settings
# and /etc/profile.d/tailscale.sh are written by cloud-init.

VERSION="${1:-latest}"
BASE="https://pkgs.tailscale.com/stable"
DEST="/opt/tailscale/bin"

case "$(uname -m)" in
  x86_64)  ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *) echo "ERROR: unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac

if [[ "${VERSION}" == "latest" ]]; then
  VERSION=$(curl -fsSL "${BASE}/?mode=json" \
    | grep -oE '"TarballsVersion": *"[^"]+"' | sed -E 's/.*"([^"]+)"$/\1/')
  [[ -n "${VERSION}" ]] || { echo "ERROR: could not read the latest version from ${BASE}" >&2; exit 1; }
fi

TGZ="tailscale_${VERSION}_${ARCH}.tgz"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT

echo "==> Downloading ${TGZ}"
curl -fsSLo "${TMP}/${TGZ}" "${BASE}/${TGZ}"
SUM=$(curl -fsSL "${BASE}/${TGZ}.sha256" | awk '{print $1}')
echo "${SUM}  ${TMP}/${TGZ}" | sha256sum -c -

tar -xzf "${TMP}/${TGZ}" -C "${TMP}"
install -d -m 0755 "${DEST}"
install -m 0755 "${TMP}/tailscale_${VERSION}_${ARCH}/tailscale" \
                "${TMP}/tailscale_${VERSION}_${ARCH}/tailscaled" "${DEST}/"

# SELinux (enforcing on SL Micro): label the binaries like /usr/bin so systemd
# runs tailscaled as an ordinary unconfined service
if command -v selinuxenabled >/dev/null && selinuxenabled; then
  chcon -t bin_t "${DEST}/tailscale" "${DEST}/tailscaled" || true
fi

systemctl daemon-reload
systemctl enable tailscaled
systemctl restart tailscaled
echo "==> Tailscale $("${DEST}/tailscale" version | head -1) installed in ${DEST}"
