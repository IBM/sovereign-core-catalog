#!/usr/bin/env bash
# Phase 3 — Write image-mapping.txt into the repo.
#
# Usage: ./3-create-image-mapping.sh --repo-dir <path>
#
# Required environment variables:
#   BYOP_REGISTRY  e.g. registry-quay-quay-enterprise.apps.<domain>

set -euo pipefail

[[ $# -lt 2 || "$1" != "--repo-dir" ]] && echo "Usage: $0 --repo-dir <path>" && exit 1
REPO_DIR="$2"
[[ ! -d "$REPO_DIR" ]] && echo "ERROR: repo directory not found: $REPO_DIR" && exit 1

for var in BYOP_REGISTRY; do
  [[ -z "${!var:-}" ]] && echo "ERROR: $var is not set" && exit 1
done

cat > "${REPO_DIR}/image-mapping.txt" <<EOF
BYOP_REGISTRY -> ${BYOP_REGISTRY}
EOF

echo "[3-create-image-mapping] Written: ${REPO_DIR}/image-mapping.txt"
