#!/usr/bin/env bash
# pack.sh — create distribution archives, excluding macOS extended-attribute files
#
# Run from demo-setup/ or from its parent directory.
# Output:
#   demo-setup/archive/sample.tar.gz      — byop-sample-repo (services + tools)
#   demo-setup/archive/byop-broker.tar.gz — byop-broker
#   <parent>/demo-setup.tar.gz            — the full demo-setup folder

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(dirname "${SCRIPT_DIR}")"
ARCHIVE_DIR="${SCRIPT_DIR}/archive"

mkdir -p "${ARCHIVE_DIR}"

# COPYFILE_DISABLE=1 prevents macOS tar from injecting ._* AppleDouble entries.
export COPYFILE_DISABLE=1

TAR_EXCLUDE=(
  --exclude='._*'
  --exclude='services/langfusehelm'
  --exclude='.DS_Store'
)

echo "==> Packing byop-sample-repo  →  archive/sample.tar.gz"
gtar -czf "${ARCHIVE_DIR}/sample.tar.gz" \
  "${TAR_EXCLUDE[@]}" \
  -C "${PARENT_DIR}" \
  byop-sample-repo/services \
  byop-sample-repo/tools

echo "==> Packing byop-broker  →  archive/byop-broker.tar.gz"
gtar -czf "${ARCHIVE_DIR}/byop-broker.tar.gz" \
  "${TAR_EXCLUDE[@]}" \
  -C "${PARENT_DIR}" \
  byop-broker/argocd \
  byop-broker/broker \
  byop-broker/catalog-app \
  byop-broker/chart \
  byop-broker/gitea

echo "==> Packing demo-setup  →  ../demo-setup.tar.gz"
gtar -czf "${PARENT_DIR}/demo-setup.tar.gz" \
  "${TAR_EXCLUDE[@]}" \
  -C "${PARENT_DIR}" \
  demo-setup

echo "Done."
echo "  ${ARCHIVE_DIR}/sample.tar.gz"
echo "  ${ARCHIVE_DIR}/byop-broker.tar.gz"
echo "  ${PARENT_DIR}/demo-setup.tar.gz"
