#!/usr/bin/env bash
# Render the diagrams and copy the PNGs next to this script (Diagram/homelab.png, Diagram/kubernetes.png).
# Needs: uv, rsvg-convert (librsvg), Fira Sans + Fira Code fonts.
set -euo pipefail
cd "$(dirname "$0")"
# third-party icons aren't committed; fetch them once (or when new ones are added to fetch_icons.py)
if [[ ! -f icons/harvester.svg || "${1:-}" == "--icons" ]]; then
  uv run python fetch_icons.py
fi
uv run python build.py
cp out/homelab.png homelab.png
uv run python build_k8s.py
cp out/kubernetes.png kubernetes.png
echo "updated $(pwd)/homelab.png $(pwd)/kubernetes.png"
