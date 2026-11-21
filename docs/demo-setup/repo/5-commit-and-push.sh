#!/usr/bin/env bash
# Phase 5 — Commit all changes and push to Gitea.
#
# Usage: ./5-commit-and-push.sh --repo-dir <path>
#
# Required environment variables:
#   GITEA_SSH_KEY_PATH path to Ed25519 private key, e.g. ~/.ssh/gitea_ed25519

set -euo pipefail

[[ $# -lt 2 || "$1" != "--repo-dir" ]] && echo "Usage: $0 --repo-dir <path>" && exit 1
REPO_DIR="$2"
[[ ! -d "$REPO_DIR" ]] && echo "ERROR: repo directory not found: $REPO_DIR" && exit 1

for var in GITEA_SSH_KEY_PATH; do
  [[ -z "${!var:-}" ]] && echo "ERROR: $var is not set" && exit 1
done

[[ ! -f "${GITEA_SSH_KEY_PATH/#\~/$HOME}" ]] && echo "ERROR: SSH key not found: $GITEA_SSH_KEY_PATH" && exit 1

command -v git &>/dev/null || { echo "ERROR: git not found in PATH"; exit 1; }

GIT_SSH_COMMAND="ssh -i ${GITEA_SSH_KEY_PATH/#\~/$HOME} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

cd "${REPO_DIR}"

# git commit requires user.name and user.email to be configured.
# If neither global nor local config provides them, set local defaults.
if [[ -z "$(git config user.name 2>/dev/null)" ]]; then
  git config user.name "gori-admin"
  echo "[5-commit-and-push] git user.name not set — defaulted to 'gori-admin'"
fi
if [[ -z "$(git config user.email 2>/dev/null)" ]]; then
  git config user.email "gori-admin@local"
  echo "[5-commit-and-push] git user.email not set — defaulted to 'gori-admin@local'"
fi

git add .
if git diff --cached --quiet; then
  echo "[5-commit-and-push] Nothing to commit — skipping."
else
  git commit -m "chore: initialize gitops service definitions"
fi
GIT_SSH_COMMAND="${GIT_SSH_COMMAND}" git push

echo "[5-commit-and-push] Done."
