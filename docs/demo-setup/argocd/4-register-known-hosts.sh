#!/usr/bin/env bash
# Phase 4 — Register the Gitea SSH host key in ArgoCD's known_hosts ConfigMap.
#
# Required environment variables:
#   GITEA_HOST      from show-gitea-outputs.sh
#   GITEA_SSH_PORT  from show-gitea-outputs.sh

set -euo pipefail

for var in GITEA_HOST GITEA_SSH_PORT; do
  [[ -z "${!var:-}" ]] && echo "ERROR: $var is not set" && exit 1
done

for tool in oc ssh-keyscan python3; do
  command -v "$tool" &>/dev/null || { echo "ERROR: $tool not found in PATH"; exit 1; }
done

oc whoami &>/dev/null || { echo "ERROR: cannot connect to cluster — check kubeconfig"; exit 1; }

GITEA_KEY=$(ssh-keyscan -p "${GITEA_SSH_PORT}" "${GITEA_HOST}" 2>/dev/null | grep -v '^#')
[[ -z "$GITEA_KEY" ]] && echo "ERROR: ssh-keyscan returned nothing for ${GITEA_HOST}:${GITEA_SSH_PORT}" && exit 1

KNOWN_HOSTS_TMP="/tmp/argocd-known-hosts-$$.txt"
CURRENT=$(oc get cm argocd-ssh-known-hosts-cm -n argocd -o jsonpath="{.data.ssh_known_hosts}" 2>/dev/null || true)
if echo "$CURRENT" | grep -qF "${GITEA_HOST}"; then
  echo "[4-register-known-hosts] Key for ${GITEA_HOST} already present — skipping append."
  printf "%s\n" "$CURRENT" > "${KNOWN_HOSTS_TMP}"
else
  printf "%s\n%s\n" "$CURRENT" "$GITEA_KEY" > "${KNOWN_HOSTS_TMP}"
fi

PATCH=$(python3 -c "
import json, sys
data = open(sys.argv[1]).read()
print(json.dumps({'data': {'ssh_known_hosts': data}}))
" "${KNOWN_HOSTS_TMP}")
oc patch configmap argocd-ssh-known-hosts-cm -n argocd --type merge -p "${PATCH}"
rm -f "${KNOWN_HOSTS_TMP}"

echo "[4-register-known-hosts] Done."
