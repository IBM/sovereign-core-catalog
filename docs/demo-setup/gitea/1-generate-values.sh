#!/usr/bin/env bash
# Phase 1 — Generate the Helm values file from environment variables.
#
# Usage: ./1-generate-values.sh --source <path-to-byop-broker>
#
# Required environment variables:
#   QUAY_REGISTRY   e.g. registry-quay-quay-enterprise.apps.<domain>
#   CLUSTER_DOMAIN  e.g. apps.mycluster.example.com
#   GITEA_PASSWORD  admin password for the gitops user

set -euo pipefail

[[ $# -lt 2 || "$1" != "--source" ]] && echo "Usage: $0 --source <path-to-byop-broker>" && exit 1
SOURCE_DIR="$2"
[[ ! -d "$SOURCE_DIR" ]] && echo "ERROR: directory not found: $SOURCE_DIR" && exit 1

for var in QUAY_REGISTRY CLUSTER_DOMAIN GITEA_PASSWORD; do
  [[ -z "${!var:-}" ]] && echo "ERROR: $var is not set" && exit 1
done

# GITEA_PASSWORD is embedded in double-quoted YAML strings.
# Reject characters that would break YAML double-quoted syntax.
if [[ "${GITEA_PASSWORD}" =~ [\"\\$] ]]; then
  echo 'ERROR: GITEA_PASSWORD contains a character not allowed in this context (", \, $).'
  echo '       Please choose a password that does not contain these characters.'
  exit 1
fi

VALUES_FILE="${SOURCE_DIR}/gitea/values-generated.yaml"

cat > "${VALUES_FILE}" <<EOF
image:
  registry: "${QUAY_REGISTRY}"
  repository: "gitea/gitea"

gitea:
  config:
    server:
      DOMAIN: "gitea-gitea.${CLUSTER_DOMAIN}"

route:
  enabled: true

storage:
  persistentVolumeClaimName:
  requestedSize: 10Gi

postgres:
  enabled: true
  image:
    registry: "${QUAY_REGISTRY}"
    repository: "gitea/postgres"
    tag: "13.12"
  settings:
    superuserPassword: "${GITEA_PASSWORD}"
  userDatabase:
    name: "gitea"
    user: "gitea"
    password: "${GITEA_PASSWORD}"
  storage:
    requestedSize: 10Gi

redis:
  enabled: true
  image:
    registry: "${QUAY_REGISTRY}"
    repository: "gitea/redis"
EOF

echo "[1-generate-values] Written: ${VALUES_FILE}"
