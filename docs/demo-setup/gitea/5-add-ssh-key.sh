#!/usr/bin/env bash
# Phase 5 — Add the SSH public key to the Gitea admin user.
#
# Required environment variables:
#   CLUSTER_DOMAIN     e.g. apps.mycluster.example.com
#   GITEA_PASSWORD     admin password for the gitops user
#   GITEA_SSH_KEY_PATH path to Ed25519 private key, e.g. ~/.ssh/gitea_ed25519

set -euo pipefail

for var in CLUSTER_DOMAIN GITEA_PASSWORD GITEA_SSH_KEY_PATH; do
  [[ -z "${!var:-}" ]] && echo "ERROR: $var is not set" && exit 1
done

[[ ! -f "${GITEA_SSH_KEY_PATH/#\~/$HOME}.pub" ]] && echo "ERROR: SSH public key not found: ${GITEA_SSH_KEY_PATH}.pub" && exit 1

command -v curl &>/dev/null || { echo "ERROR: curl not found in PATH"; exit 1; }

GITEA_URL="https://gitea-gitea.${CLUSTER_DOMAIN}"
GITEA_SSH_PUBLIC_KEY=$(cat "${GITEA_SSH_KEY_PATH/#\~/$HOME}.pub")

HTTP_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" -X POST "${GITEA_URL}/api/v1/user/keys" \
  -H "Content-Type: application/json" \
  -u "gitops:${GITEA_PASSWORD}" \
  -d "{\"key\": \"${GITEA_SSH_PUBLIC_KEY}\", \"read_only\": false, \"title\": \"gitops-key\"}")

if [[ "$HTTP_STATUS" == "201" ]]; then
  echo "[5-add-ssh-key] SSH key registered."
elif [[ "$HTTP_STATUS" == "422" ]]; then
  echo "[5-add-ssh-key] SSH key already registered — skipping."
else
  echo "ERROR: unexpected HTTP status ${HTTP_STATUS} from Gitea API" && exit 1
fi

echo "[5-add-ssh-key] Done."
