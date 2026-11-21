#!/usr/bin/env bash
# Phase 1 — Clone the gitops repository from Gitea.
#
# Usage: ./1-clone-repo.sh [--target-dir <dir>]
#
# Optional:
#   --target-dir  Local directory to clone into (default: ./gitops)
#
# Required environment variables:
#   GITEA_HOST         from Gitea deployment
#   GITEA_SSH_PORT     from Gitea deployment
#   GITEA_USER_ID      from Gitea deployment
#   GITEA_SSH_KEY_PATH path to Ed25519 private key, e.g. ~/.ssh/gitea_ed25519

set -euo pipefail

TARGET_DIR="./gitops"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-dir) TARGET_DIR="$2"; shift 2 ;;
    *) echo "Usage: $0 [--target-dir <dir>]"; exit 1 ;;
  esac
done

for var in GITEA_HOST GITEA_SSH_PORT GITEA_USER_ID GITEA_SSH_KEY_PATH; do
  [[ -z "${!var:-}" ]] && echo "ERROR: $var is not set" && exit 1
done

[[ ! -f "${GITEA_SSH_KEY_PATH/#\~/$HOME}" ]] && echo "ERROR: SSH key not found: $GITEA_SSH_KEY_PATH" && exit 1

command -v git &>/dev/null || { echo "ERROR: git not found in PATH"; exit 1; }

GITEA_SSH_URL="ssh://${GITEA_USER_ID}@${GITEA_HOST}:${GITEA_SSH_PORT}/gitops/gitops.git"
GIT_SSH_COMMAND="ssh -i ${GITEA_SSH_KEY_PATH/#\~/$HOME} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

GIT_SSH_COMMAND="${GIT_SSH_COMMAND}" git clone "${GITEA_SSH_URL}" "${TARGET_DIR}"

echo "[1-clone-repo] Cloned into: ${TARGET_DIR}"
