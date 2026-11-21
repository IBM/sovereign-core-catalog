#!/usr/bin/env bash
# Supplemental — Mirror additional service images to internal Quay.
# These images are required depending on which service plans are offered.
# This script is NOT called by the orchestrator (deploy-byop-broker.sh).
# Run it manually for any images needed beyond the core deployment.
#
# NOTE: This script covers Helm-deployed service images only.
# OLM-based services are NOT covered here.
# Mirror their images using oc-mirror with the service's imagesetconfiguration-<env>.yaml
# and the new-olm-service-mirroring skill.
#
# Required environment variables:
#   QUAY_REGISTRY    e.g. registry-quay-quay-enterprise.apps.<domain>
#   BYOP_ROBOT_TOKEN robot account token (byop+byop_push)

set -euo pipefail

for var in QUAY_REGISTRY BYOP_ROBOT_TOKEN; do
  [[ -z "${!var:-}" ]] && echo "ERROR: $var is not set" && exit 1
done

command -v podman &>/dev/null || { echo "ERROR: podman not found in PATH"; exit 1; }

set +e

echo "${BYOP_ROBOT_TOKEN}" | podman login -u="byop+byop_push" --password-stdin "${QUAY_REGISTRY}"

# valkey
podman pull docker.io/valkey/valkey:9.0.4
podman tag  docker.io/valkey/valkey:9.0.4 "${QUAY_REGISTRY}/byop/valkey:9.0.4"
podman push --tls-verify=false "${QUAY_REGISTRY}/byop/valkey:9.0.4"

# postgres
podman pull docker.io/library/postgres:17.10
podman tag  docker.io/library/postgres:17.10 "${QUAY_REGISTRY}/byop/postgres:17.10"
podman push --tls-verify=false "${QUAY_REGISTRY}/byop/postgres:17.10"

# mysql
podman pull docker.io/library/mysql:9.7.1
podman tag  docker.io/library/mysql:9.7.1 "${QUAY_REGISTRY}/byop/mysql:9.7.1"
podman push --tls-verify=false "${QUAY_REGISTRY}/byop/mysql:9.7.1"

# rabbitmq
podman pull docker.io/library/rabbitmq:4.3.2
podman tag  docker.io/library/rabbitmq:4.3.2 "${QUAY_REGISTRY}/byop/rabbitmq:4.3.2"
podman push --tls-verify=false "${QUAY_REGISTRY}/byop/rabbitmq:4.3.2"

# odoo
podman pull docker.io/library/odoo:18.0
podman tag  docker.io/library/odoo:18.0 "${QUAY_REGISTRY}/byop/odoo:18.0"
podman push --tls-verify=false "${QUAY_REGISTRY}/byop/odoo:18.0"

# keycloak
podman pull docker.io/keycloak/keycloak:26.6
podman tag  docker.io/keycloak/keycloak:26.6 "${QUAY_REGISTRY}/byop/keycloak:26.6"
podman push --tls-verify=false "${QUAY_REGISTRY}/byop/keycloak:26.6"

# memcached
podman pull docker.io/library/memcached:1.6.42
podman tag  docker.io/library/memcached:1.6.42 "${QUAY_REGISTRY}/byop/memcached:1.6.42"
podman push --tls-verify=false "${QUAY_REGISTRY}/byop/memcached:1.6.42"

# redis
podman pull docker.io/library/redis:8.6.3
podman tag  docker.io/library/redis:8.6.3 "${QUAY_REGISTRY}/byop/redis:8.6.3"
podman push --tls-verify=false "${QUAY_REGISTRY}/byop/redis:8.6.3"

# nginx
podman pull docker.io/library/nginx:1.29.8-alpine
podman tag  docker.io/library/nginx:1.29.8-alpine "${QUAY_REGISTRY}/byop/nginx:1.29.8-alpine"
podman push --tls-verify=false "${QUAY_REGISTRY}/byop/nginx:1.29.8-alpine"

# busybox — pulled from :latest and published as :stable (intentional alias)
podman pull docker.io/library/busybox:stable
podman tag  docker.io/library/busybox:stable "${QUAY_REGISTRY}/byop/busybox:stable"
podman push --tls-verify=false "${QUAY_REGISTRY}/byop/busybox:stable"
podman pull docker.io/library/busybox:latest
podman tag  docker.io/library/busybox:latest "${QUAY_REGISTRY}/byop/busybox:latest"
podman push --tls-verify=false "${QUAY_REGISTRY}/byop/busybox:latest"

# vault
podman pull docker.io/hashicorp/vault:1.17.2
podman tag  docker.io/hashicorp/vault:1.17.2 "${QUAY_REGISTRY}/byop/vault:1.17.2"
podman push --tls-verify=false "${QUAY_REGISTRY}/byop/vault:1.17.2"

# etcd
podman pull quay.io/coreos/etcd:v3.4.2
podman tag  quay.io/coreos/etcd:v3.4.2 "${QUAY_REGISTRY}/byop/etcd:v3.4.2"
podman push --tls-verify=false "${QUAY_REGISTRY}/byop/etcd:v3.4.2"

# memcached-exporter (sidecar used by memcachedhelm)
podman pull docker.io/prom/memcached-exporter:v0.15.0
podman tag  docker.io/prom/memcached-exporter:v0.15.0 "${QUAY_REGISTRY}/byop/memcached-exporter:v0.15.0"
podman push --tls-verify=false "${QUAY_REGISTRY}/byop/memcached-exporter:v0.15.0"

# langflow — backend + frontend (langflowhelm)
podman pull docker.io/langflowai/langflow:1.10.2
podman tag  docker.io/langflowai/langflow:1.10.2 "${QUAY_REGISTRY}/byop/langflow:1.10.2"
podman push --tls-verify=false "${QUAY_REGISTRY}/byop/langflow:1.10.2"

podman pull docker.io/langflowai/langflow-frontend:1.10.2
podman tag  docker.io/langflowai/langflow-frontend:1.10.2 "${QUAY_REGISTRY}/byop/langflow-frontend:1.10.2"
podman push --tls-verify=false "${QUAY_REGISTRY}/byop/langflow-frontend:1.10.2"

# olgranitehelm — custom Ollama+Granite4 image (must be built from source first)
# Build requires internet access; run on a machine that can reach ollama.com:
#   podman build -t olgranitehelm:0.32.2 services/olgranitehelm/docker/
podman tag  olgranitehelm:0.32.2 "${QUAY_REGISTRY}/byop/olgranitehelm:0.32.2"
podman push --tls-verify=false "${QUAY_REGISTRY}/byop/olgranitehelm:0.32.2"

echo "[3-mirror-extra-images] Done."
