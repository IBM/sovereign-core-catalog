#!/usr/bin/env bash
# Phase 2 — Mirror Gitea, Postgres and Redis images to internal Quay.
#
# Required environment variables:
#   QUAY_REGISTRY      e.g. registry-quay-quay-enterprise.apps.<domain>
#   GITEA_ROBOT_TOKEN  robot account token (gitea+gitea_push)

set -euo pipefail

for var in QUAY_REGISTRY GITEA_ROBOT_TOKEN; do
  [[ -z "${!var:-}" ]] && echo "ERROR: $var is not set" && exit 1
done

command -v podman &>/dev/null || { echo "ERROR: podman not found in PATH"; exit 1; }

echo "${GITEA_ROBOT_TOKEN}" | podman login -u="gitea+gitea_push" --password-stdin "${QUAY_REGISTRY}"

podman pull docker.io/gitea/gitea:1.26.2
podman tag  docker.io/gitea/gitea:1.26.2 "${QUAY_REGISTRY}/gitea/gitea:1.26.2"
podman push "${QUAY_REGISTRY}/gitea/gitea:1.26.2"

podman pull docker.io/library/postgres:13.12
podman tag  docker.io/library/postgres:13.12 "${QUAY_REGISTRY}/gitea/postgres:13.12"
podman push "${QUAY_REGISTRY}/gitea/postgres:13.12"

podman pull docker.io/library/redis:7.0.12
podman tag  docker.io/library/redis:7.0.12 "${QUAY_REGISTRY}/gitea/redis:7.0.12"
podman push "${QUAY_REGISTRY}/gitea/redis:7.0.12"

echo "[2-mirror-images] Done."
