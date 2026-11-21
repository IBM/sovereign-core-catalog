#!/usr/bin/env bash
# Phase 1 — Mirror ArgoCD and Redis images to an internal Quay registry.
#
# Required environment variables:
#   QUAY_REGISTRY      e.g. registry-quay-quay-enterprise.apps.<domain>
#   ARGOCD_ROBOT_TOKEN robot account token (argoproj+argocd_push)

set -euo pipefail

for var in QUAY_REGISTRY ARGOCD_ROBOT_TOKEN; do
  [[ -z "${!var:-}" ]] && echo "ERROR: $var is not set" && exit 1
done

command -v podman &>/dev/null || { echo "ERROR: podman not found in PATH"; exit 1; }

echo "${ARGOCD_ROBOT_TOKEN}" | podman login -u="argoproj+argocd_push" --password-stdin "${QUAY_REGISTRY}"

podman pull quay.io/argoproj/argocd:v3.4.4
podman tag  quay.io/argoproj/argocd:v3.4.4 "${QUAY_REGISTRY}/argoproj/argocd:v3.4.4"
podman push "${QUAY_REGISTRY}/argoproj/argocd:v3.4.4"

podman pull docker.io/library/redis:8.2.3-alpine
podman tag  docker.io/library/redis:8.2.3-alpine "${QUAY_REGISTRY}/argoproj/redis:8.2.3-alpine"
podman push "${QUAY_REGISTRY}/argoproj/redis:8.2.3-alpine"

echo "[1-mirror-images] Done."
