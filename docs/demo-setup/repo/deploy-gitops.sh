#!/usr/bin/env bash
# Orchestrator — runs all gitops repo setup phases in order.
# Each phase script can also be run independently.
#
# Usage: ./deploy-gitops.sh [--target-dir <dir>]
#
# Optional:
#   --target-dir  Local directory to clone into (default: ./gitops)
#
# Required environment variables:
#   BYOP_REGISTRY      e.g. registry-quay-quay-enterprise.apps.<domain>
#   GITEA_HOST         from Gitea deployment
#   GITEA_SSH_PORT     from Gitea deployment
#   GITEA_USER_ID      from Gitea deployment
#   GITEA_SSH_KEY_PATH path to Ed25519 private key, e.g. ~/.ssh/gitea_ed25519

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="./gitops"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-dir) TARGET_DIR="$2"; shift 2 ;;
    *) echo "Usage: $0 [--target-dir <dir>]"; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Validate tools — all phases combined
# ---------------------------------------------------------------------------
for tool in git tar; do
  command -v "$tool" &>/dev/null || { echo "ERROR: $tool not found in PATH"; exit 1; }
done

# ---------------------------------------------------------------------------
# Validate environment variables — all phases combined
# ---------------------------------------------------------------------------
for var in BYOP_REGISTRY GITEA_HOST GITEA_SSH_PORT GITEA_USER_ID GITEA_SSH_KEY_PATH; do
  [[ -z "${!var:-}" ]] && echo "ERROR: $var is not set" && exit 1
done

[[ ! -f "${GITEA_SSH_KEY_PATH/#\~/$HOME}" ]] && echo "ERROR: SSH key not found: $GITEA_SSH_KEY_PATH" && exit 1

# ---------------------------------------------------------------------------
# Validate archive exists
# ---------------------------------------------------------------------------
ARCHIVE="${SCRIPT_DIR}/../archive/sample.tar.gz"
[[ ! -f "$ARCHIVE" ]] && echo "ERROR: archive not found: $ARCHIVE" && exit 1

# ---------------------------------------------------------------------------
# Run phases
# ---------------------------------------------------------------------------
echo "==> Phase 1: Clone gitops repository"
"${SCRIPT_DIR}/1-clone-repo.sh" --target-dir "${TARGET_DIR}"

echo "==> Phase 2: Extract service definitions"
"${SCRIPT_DIR}/2-extract-content.sh" --repo-dir "${TARGET_DIR}"

echo "==> Phase 3: Create image mapping"
"${SCRIPT_DIR}/3-create-image-mapping.sh" --repo-dir "${TARGET_DIR}"

echo "==> Phase 4: Create helper scripts"
"${SCRIPT_DIR}/4-create-helper-scripts.sh" --repo-dir "${TARGET_DIR}"

echo "==> Phase 5: Commit and push"
"${SCRIPT_DIR}/5-commit-and-push.sh" --repo-dir "${TARGET_DIR}"

echo "Done."
