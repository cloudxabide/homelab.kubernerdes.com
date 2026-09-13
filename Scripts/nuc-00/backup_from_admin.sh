#!/bin/bash
set -euo pipefail

# backup_from_admin.sh — Pull config that's been edited live on nuc-00 back
# into this repo's Files/nuc-00/ mirror tree.
#
# Files/nuc-00/ mirrors nuc-00's filesystem 1:1 (Files/nuc-00/etc/named.conf
# -> /etc/named.conf on nuc-00, etc). post_install_infra.sh only pushes that
# tree OUT to nuc-00 — nothing pulls edits back. Run this from your local
# checkout after editing files directly on nuc-00 (e.g. the iPXE menu under
# /srv/www/htdocs/harvester/harvester) so those edits land in git instead of
# only living on the live host.
#
# Usage:
#   Scripts/nuc-00/backup_from_admin.sh [relative/path/under/Files/nuc-00]
#
# With no argument, backs up srv/www/htdocs/harvester/harvester (the iPXE
# menu/config tree). Pass a different path to pull back other mirrored
# config, e.g.:
#   Scripts/nuc-00/backup_from_admin.sh etc/dhcpd.d
#
# Does NOT pass --delete: files removed on nuc-00 are left alone locally so
# this can't silently delete uncommitted local work. Review `git status` /
# `git diff` after running and remove anything stale yourself.

ADMIN_USER="${ADMIN_USER:-mansible}"
# "nuc-00" only resolves on-network via the nuc-00-hosted DNS itself; from an
# arbitrary machine (e.g. your laptop, off the homelab DNS) it won't resolve,
# so default to the known admin IP (see Scripts/env.sh ADMIN_IP) and let
# ADMIN_HOST override to a hostname if your resolver does know it.
ADMIN_HOST="${ADMIN_HOST:-10.10.12.10}"
REL_PATH="${1:-srv/www/htdocs/harvester/harvester}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEST_DIR="${REPO_ROOT}/Files/nuc-00/${REL_PATH}"

mkdir -p "${DEST_DIR}"

echo "==> Pulling ${ADMIN_USER}@${ADMIN_HOST}:/${REL_PATH}/ -> ${DEST_DIR}/"
rsync -avz "${ADMIN_USER}@${ADMIN_HOST}:/${REL_PATH}/" "${DEST_DIR}/"

echo
echo "==> Done. Review changes with:"
echo "    git -C \"${REPO_ROOT}\" status Files/nuc-00/${REL_PATH}"
echo "    git -C \"${REPO_ROOT}\" diff Files/nuc-00/${REL_PATH}"
