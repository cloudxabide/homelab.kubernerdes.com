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
# With no argument, backs up every path already tracked in git under
# Files/nuc-00/. Top-level roots (etc/, srv/, var/) are NEVER synced as whole
# directories — that would pull the entire live /etc, /srv, /var (including
# /etc/shadow, /etc/sudoers, NetworkManager profiles, apparmor.d, hundreds of
# unrelated distro files, permission-denied noise, etc). Instead:
#   - a tracked file sitting directly under a top-level root (e.g.
#     etc/named.conf, etc/dhcpd.conf) is pulled as that single file
#   - a tracked file two or more levels deep is treated as belonging to a
#     dedicated config subtree (e.g. etc/dhcpd.d/, srv/tftpboot/,
#     srv/www/htdocs/harvester/harvester/, var/lib/named/master/) and that
#     whole subtree is pulled recursively, so new files added there on
#     nuc-00 are picked up too
#
# Pass a specific path to pull back just that subtree (or a brand-new one
# not yet tracked in git), e.g.:
#   Scripts/nuc-00/backup_from_admin.sh srv/www/htdocs/harvester/harvester
#   Scripts/nuc-00/backup_from_admin.sh etc/some-new-thing.conf
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FILES_DIR="${REPO_ROOT}/Files/nuc-00"

DIR_TARGETS=()
FILE_TARGETS=()

if [[ -n "${1:-}" ]]; then
  if [[ -d "${FILES_DIR}/$1" ]]; then
    DIR_TARGETS+=("$1")
  else
    FILE_TARGETS+=("$1")
  fi
else
  # bash 3.2 (macOS default) has no associative arrays, so dedup dirs via
  # sort -u instead of a SEEN_DIRS map.
  RAW_DIRS=()
  while IFS= read -r REL_FILE; do
    REL_DIR="$(dirname "${REL_FILE}")"
    if [[ "${REL_DIR}" == "." ]]; then
      FILE_TARGETS+=("${REL_FILE}")
    elif [[ "${REL_DIR}" != */* ]]; then
      # exactly one path component (e.g. "etc") — a top-level root, never
      # synced whole; pull the individual file instead
      FILE_TARGETS+=("${REL_FILE}")
    else
      RAW_DIRS+=("${REL_DIR}")
    fi
  done < <(cd "${REPO_ROOT}" && git ls-files -- Files/nuc-00 | sed 's#^Files/nuc-00/##')

  if [[ "${#RAW_DIRS[@]}" -gt 0 ]]; then
    while IFS= read -r REL_DIR; do
      DIR_TARGETS+=("${REL_DIR}")
    done < <(printf '%s\n' "${RAW_DIRS[@]}" | sort -u)
  fi
fi

if [[ "${#DIR_TARGETS[@]}" -gt 0 ]]; then
  for REL_PATH in "${DIR_TARGETS[@]}"; do
    DEST_DIR="${FILES_DIR}/${REL_PATH}"
    mkdir -p "${DEST_DIR}"
    echo "==> Pulling ${ADMIN_USER}@${ADMIN_HOST}:/${REL_PATH}/ -> ${DEST_DIR}/"
    rsync -avz "${ADMIN_USER}@${ADMIN_HOST}:/${REL_PATH}/" "${DEST_DIR}/"
    echo
  done
fi

if [[ "${#FILE_TARGETS[@]}" -gt 0 ]]; then
  for REL_PATH in "${FILE_TARGETS[@]}"; do
    DEST_FILE="${FILES_DIR}/${REL_PATH}"
    mkdir -p "$(dirname "${DEST_FILE}")"
    echo "==> Pulling ${ADMIN_USER}@${ADMIN_HOST}:/${REL_PATH} -> ${DEST_FILE}"
    rsync -avz "${ADMIN_USER}@${ADMIN_HOST}:/${REL_PATH}" "${DEST_FILE}"
    echo
  done
fi

echo "==> Done. Review changes with:"
echo "    git -C \"${REPO_ROOT}\" status Files/nuc-00"
echo "    git -C \"${REPO_ROOT}\" diff Files/nuc-00"
