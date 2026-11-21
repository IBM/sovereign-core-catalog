#!/usr/bin/env bash
# Phase 4 — Create the Gitea admin user inside the pod.
#
# Required environment variables:
#   GITEA_PASSWORD  admin password for the gitops user
#   GITEA_EMAIL     admin email for the gitops user

set -euo pipefail

for var in GITEA_PASSWORD GITEA_EMAIL; do
  [[ -z "${!var:-}" ]] && echo "ERROR: $var is not set" && exit 1
done

command -v oc &>/dev/null || { echo "ERROR: oc not found in PATH"; exit 1; }
oc whoami &>/dev/null || { echo "ERROR: cannot connect to cluster — check kubeconfig"; exit 1; }

GITEA_POD=$(oc get pod -n gitea -l app.kubernetes.io/name=gitea -o jsonpath='{.items[0].metadata.name}')
[[ -z "$GITEA_POD" ]] && echo "ERROR: no Gitea pod found in namespace gitea" && exit 1

if oc exec -n gitea "${GITEA_POD}" -- gitea admin user list 2>/dev/null | grep -q "gitops"; then
  echo "[4-create-admin-user] User 'gitops' already exists — skipping."
else
  oc exec -n gitea "${GITEA_POD}" -- \
    gitea admin user create \
    --username "gitops" \
    --password "${GITEA_PASSWORD}" \
    --email "${GITEA_EMAIL}" \
    --admin \
    --must-change-password=false
fi

echo "[4-create-admin-user] Done."
