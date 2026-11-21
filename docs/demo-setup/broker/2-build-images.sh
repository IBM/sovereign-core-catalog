#!/usr/bin/env bash
# Phase 2 — Build broker and catalog-app images from source.
#
# Usage: ./2-build-images.sh --source <path-to-byop-broker>

set -euo pipefail

[[ $# -lt 2 || "$1" != "--source" ]] && echo "Usage: $0 --source <path-to-byop-broker>" && exit 1
SOURCE_DIR="$2"
[[ ! -d "$SOURCE_DIR" ]] && echo "ERROR: directory not found: $SOURCE_DIR" && exit 1

command -v podman &>/dev/null || { echo "ERROR: podman not found in PATH"; exit 1; }

SOURCE_ABS="$(cd "${SOURCE_DIR}" && pwd)"

cd "${SOURCE_ABS}/catalog-app"
podman build --platform linux/amd64 -t localhost/byop-catalog-app:1.0.4-01 .

cd "${SOURCE_ABS}/broker"
podman build --platform linux/amd64 -t localhost/byop-broker:1.5.5-01 .

echo "[2-build-images] Done."
