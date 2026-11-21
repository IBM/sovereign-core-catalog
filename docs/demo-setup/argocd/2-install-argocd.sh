#!/usr/bin/env bash
# Phase 2 — Install ArgoCD and wait for the server to be ready.
#
# Usage: ./2-install-argocd.sh --source <path-to-byop-broker>
#
# Required environment variables:
#   QUAY_REGISTRY  e.g. registry-quay-quay-enterprise.apps.<domain>

set -euo pipefail

[[ $# -lt 2 || "$1" != "--source" ]] && echo "Usage: $0 --source <path-to-byop-broker>" && exit 1
SOURCE_DIR="$2"
[[ ! -d "$SOURCE_DIR" ]] && echo "ERROR: directory not found: $SOURCE_DIR" && exit 1

for var in QUAY_REGISTRY; do
  [[ -z "${!var:-}" ]] && echo "ERROR: $var is not set" && exit 1
done

command -v oc &>/dev/null || { echo "ERROR: oc not found in PATH"; exit 1; }
oc whoami &>/dev/null || { echo "ERROR: cannot connect to cluster — check kubeconfig"; exit 1; }

cd "${SOURCE_DIR}/argocd/scripts/admin"
./argocd-install.sh \
  --namespace argocd \
  --image-repository "${QUAY_REGISTRY}/argoproj"

# Use annotation-based resource tracking — label-based tracking is limited to
# 63 chars and breaks on app names derived from long service+uuid strings.
oc patch configmap argocd-cm -n argocd --type=merge \
  -p '{"data":{"application.resourceTrackingMethod":"annotation"}}'

oc rollout status deployment/argocd-server -n argocd --timeout=5m

echo "[2-install-argocd] Done."
