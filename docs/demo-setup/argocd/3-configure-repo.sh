#!/usr/bin/env bash
# Phase 3 — Configure the Gitea repository in ArgoCD.
#
# Usage: ./3-configure-repo.sh --source <path-to-byop-broker>
#
# Required environment variables:
#   GITEA_HOST         from Gitea deployment Step 5e
#   GITEA_SSH_PORT     from Gitea deployment Step 5e
#   GITEA_USER_ID      from Gitea deployment Step 5d
#   GITEA_SSH_KEY_PATH path to Ed25519 private key, e.g. ~/.ssh/gitea_ed25519

set -euo pipefail

[[ $# -lt 2 || "$1" != "--source" ]] && echo "Usage: $0 --source <path-to-byop-broker>" && exit 1
SOURCE_DIR="$2"
[[ ! -d "$SOURCE_DIR" ]] && echo "ERROR: directory not found: $SOURCE_DIR" && exit 1

for var in GITEA_HOST GITEA_SSH_PORT GITEA_USER_ID GITEA_SSH_KEY_PATH; do
  [[ -z "${!var:-}" ]] && echo "ERROR: $var is not set" && exit 1
done

[[ ! -f "${GITEA_SSH_KEY_PATH/#\~/$HOME}" ]] && echo "ERROR: SSH key not found: $GITEA_SSH_KEY_PATH" && exit 1

command -v oc &>/dev/null || { echo "ERROR: oc not found in PATH"; exit 1; }
oc whoami &>/dev/null || { echo "ERROR: cannot connect to cluster — check kubeconfig"; exit 1; }

cd "${SOURCE_DIR}/argocd/scripts"
./argocd-configure-repo.sh \
  --namespace argocd \
  --repo-url "ssh://${GITEA_USER_ID}@${GITEA_HOST}:${GITEA_SSH_PORT}/gitops/gitops.git" \
  --ssh-key-path "${GITEA_SSH_KEY_PATH/#\~/$HOME}"

echo "[3-configure-repo] Done."
