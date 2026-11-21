#!/usr/bin/env bash
# Phase 4 — Deploy the broker chart with Helm and wait for rollout.
#
# Usage: ./4-deploy-helm.sh --source <path-to-byop-broker>

set -euo pipefail

[[ $# -lt 2 || "$1" != "--source" ]] && echo "Usage: $0 --source <path-to-byop-broker>" && exit 1
SOURCE_DIR="$2"
[[ ! -d "$SOURCE_DIR" ]] && echo "ERROR: directory not found: $SOURCE_DIR" && exit 1

VALUES_FILE="${SOURCE_DIR}/values-generated.yaml"
[[ ! -f "$VALUES_FILE" ]] && echo "ERROR: values file not found: $VALUES_FILE — run 1-generate-values.sh first" && exit 1

for tool in helm oc; do
  command -v "$tool" &>/dev/null || { echo "ERROR: $tool not found in PATH"; exit 1; }
done

oc whoami &>/dev/null || { echo "ERROR: cannot connect to cluster — check kubeconfig"; exit 1; }

cd "${SOURCE_DIR}"
helm upgrade --install byop ./chart \
  --namespace byop \
  --create-namespace \
  --values "${VALUES_FILE}"

oc rollout status deployment/byop-broker -n byop --timeout=5m
oc rollout status deployment/byop-catalog-app -n byop --timeout=5m

echo "[4-deploy-helm] Done."
