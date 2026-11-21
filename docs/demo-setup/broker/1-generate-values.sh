#!/usr/bin/env bash
# Phase 1 — Generate the Helm values file from environment variables.
#
# Usage: ./1-generate-values.sh --source <path-to-byop-broker>
#
# Required environment variables:
#   QUAY_REGISTRY      e.g. registry-quay-quay-enterprise.apps.<domain>
#   CLUSTER_DOMAIN     e.g. apps.mycluster.example.com
#   GITEA_HOST         from show-gitea-outputs.sh
#   GITEA_SSH_PORT     from show-gitea-outputs.sh
#   GITEA_USER_ID      from show-gitea-outputs.sh
#   GITEA_SSH_KEY_PATH path to Ed25519 private key, e.g. ~/.ssh/gitea_ed25519

set -euo pipefail

[[ $# -lt 2 || "$1" != "--source" ]] && echo "Usage: $0 --source <path-to-byop-broker>" && exit 1
SOURCE_DIR="$2"
[[ ! -d "$SOURCE_DIR" ]] && echo "ERROR: directory not found: $SOURCE_DIR" && exit 1

for var in QUAY_REGISTRY CLUSTER_DOMAIN GITEA_USER_ID GITEA_SSH_KEY_PATH; do
  [[ -z "${!var:-}" ]] && echo "ERROR: $var is not set" && exit 1
done

[[ ! -f "${GITEA_SSH_KEY_PATH/#\~/$HOME}" ]] && echo "ERROR: SSH key not found: $GITEA_SSH_KEY_PATH" && exit 1

SSH_PRIVATE_KEY=$(cat "${GITEA_SSH_KEY_PATH/#\~/$HOME}")
VALUES_FILE="${SOURCE_DIR}/values-generated.yaml"

# Use internal cluster DNS for broker (pod-to-pod), fallback to NodePort if set
GITEA_REPO_URL="ssh://${GITEA_USER_ID}@gitea-ssh.gitea.svc.cluster.local:22/gitops/gitops.git"

cat > "${VALUES_FILE}" <<EOF
global:
  imageRegistry: "${QUAY_REGISTRY}"
  imageOrganization: byop

cluster:
  domain: "${CLUSTER_DOMAIN}"

broker:
  image:
    tag: "1.5.5-01"

  securityContext:
    runAsNonRoot: true

  auth:
    enabled: false
    verifySSL: false

  dashboardUrlTemplate: "https://argocd-server-argocd.${CLUSTER_DOMAIN}/applications/argocd/{instance_id}?view=tree"

  gitops:
    repoUrl: "${GITEA_REPO_URL}"

  clusters:
    - server: "https://kubernetes.default.svc"
      name: "in-cluster"
      type: "hub"
      default: true

  secrets:
    sshPrivateKey: |
$(echo "${SSH_PRIVATE_KEY}" | sed 's/^/      /')

catalogApp:
  enabled: true
  image:
    tag: "1.0.4-01"
EOF

echo "[1-generate-values] Written: ${VALUES_FILE}"
