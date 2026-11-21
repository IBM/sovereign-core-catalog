#!/usr/bin/env bash
# Phase 3 — Tag and push all images to the internal Quay registry.
#
# Required environment variables:
#   QUAY_REGISTRY    e.g. registry-quay-quay-enterprise.apps.<domain>
#   BYOP_ROBOT_TOKEN robot account token (byop+byop_push)

set -euo pipefail

for var in QUAY_REGISTRY BYOP_ROBOT_TOKEN; do
  [[ -z "${!var:-}" ]] && echo "ERROR: $var is not set" && exit 1
done

command -v podman &>/dev/null || { echo "ERROR: podman not found in PATH"; exit 1; }

echo "${BYOP_ROBOT_TOKEN}" | podman login --tls-verify=false -u="byop+byop_push" --password-stdin "${QUAY_REGISTRY}"

podman tag localhost/byop-broker:1.5.5-01 "${QUAY_REGISTRY}/byop/byop-broker:1.5.5-01"
podman push --tls-verify=false "${QUAY_REGISTRY}/byop/byop-broker:1.5.5-01"

podman tag localhost/byop-catalog-app:1.0.4-01 "${QUAY_REGISTRY}/byop/byop-catalog-app:1.0.4-01"
podman push --tls-verify=false "${QUAY_REGISTRY}/byop/byop-catalog-app:1.0.4-01"

podman pull --platform linux/amd64 docker.io/library/mariadb:12.3.2
podman tag  docker.io/library/mariadb:12.3.2 "${QUAY_REGISTRY}/byop/mariadb:12.3.2"
podman push --tls-verify=false "${QUAY_REGISTRY}/byop/mariadb:12.3.2"

podman pull --platform linux/amd64 docker.io/library/mongo:7.0.34
podman tag  docker.io/library/mongo:7.0.34 "${QUAY_REGISTRY}/byop/mongo:7.0.34"
podman push --tls-verify=false "${QUAY_REGISTRY}/byop/mongo:7.0.34"

echo "[3-push-images] Done."
