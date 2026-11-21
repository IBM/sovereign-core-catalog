#!/usr/bin/env bash
# Phase 6 — Create the gitops repository in Gitea.
#
# Required environment variables:
#   CLUSTER_DOMAIN  e.g. apps.mycluster.example.com
#   GITEA_PASSWORD  admin password for the gitops user

set -euo pipefail

for var in CLUSTER_DOMAIN GITEA_PASSWORD; do
  [[ -z "${!var:-}" ]] && echo "ERROR: $var is not set" && exit 1
done

command -v curl &>/dev/null || { echo "ERROR: curl not found in PATH"; exit 1; }

GITEA_URL="https://gitea-gitea.${CLUSTER_DOMAIN}"

HTTP_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" -X POST "${GITEA_URL}/api/v1/user/repos" \
  -H "Content-Type: application/json" \
  -u "gitops:${GITEA_PASSWORD}" \
  -d '{"name": "gitops", "private": false, "auto_init": true, "default_branch": "main"}')

if [[ "$HTTP_STATUS" == "201" ]]; then
  echo "[6-create-repo] Repository created."
elif [[ "$HTTP_STATUS" == "409" ]]; then
  echo "[6-create-repo] Repository already exists — skipping."
else
  echo "ERROR: unexpected HTTP status ${HTTP_STATUS} from Gitea API" && exit 1
fi

echo "[6-create-repo] Done."
