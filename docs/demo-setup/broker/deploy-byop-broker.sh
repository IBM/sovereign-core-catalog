#!/usr/bin/env bash
# Orchestrator — runs all BYOP broker deployment phases in order.
# Each phase script can also be run independently.
#
# Usage: ./deploy-byop-broker.sh --source <path-to-byop-broker>
#
# Required environment variables:
#   QUAY_REGISTRY      e.g. registry-quay-quay-enterprise.apps.<domain>
#   BYOP_ROBOT_TOKEN   robot account token (byop+byop_push)
#   CLUSTER_DOMAIN     e.g. apps.mycluster.example.com
#   GITEA_HOST         from Gitea deployment Step 5e
#   GITEA_SSH_PORT     from Gitea deployment Step 5e
#   GITEA_USER_ID      from Gitea deployment Step 5d
#   GITEA_SSH_KEY_PATH path to Ed25519 private key, e.g. ~/.ssh/gitea_ed25519

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
[[ $# -lt 2 || "$1" != "--source" ]] && echo "Usage: $0 --source <path-to-byop-broker>" && exit 1
SOURCE_DIR="$2"
[[ ! -d "$SOURCE_DIR" ]] && echo "ERROR: directory not found: $SOURCE_DIR" && exit 1

# ---------------------------------------------------------------------------
# Validate tools — all phases combined
# ---------------------------------------------------------------------------
for tool in oc podman helm; do
  command -v "$tool" &>/dev/null || { echo "ERROR: $tool not found in PATH"; exit 1; }
done

# ---------------------------------------------------------------------------
# Validate environment variables — all phases combined
# ---------------------------------------------------------------------------
for var in QUAY_REGISTRY BYOP_ROBOT_TOKEN CLUSTER_DOMAIN GITEA_HOST GITEA_SSH_PORT GITEA_USER_ID GITEA_SSH_KEY_PATH; do
  [[ -z "${!var:-}" ]] && echo "ERROR: $var is not set" && exit 1
done

[[ ! -f "${GITEA_SSH_KEY_PATH/#\~/$HOME}" ]] && echo "ERROR: SSH key not found: $GITEA_SSH_KEY_PATH" && exit 1

# ---------------------------------------------------------------------------
# Validate cluster connectivity
# ---------------------------------------------------------------------------
oc whoami &>/dev/null || { echo "ERROR: cannot connect to cluster — check kubeconfig"; exit 1; }

# ---------------------------------------------------------------------------
# Run phases
# ---------------------------------------------------------------------------
echo "==> Phase 1: Generate values file"
"${SCRIPT_DIR}/1-generate-values.sh" --source "${SOURCE_DIR}"

echo "==> Phase 2: Build images"
"${SCRIPT_DIR}/2-build-images.sh" --source "${SOURCE_DIR}"

echo "==> Phase 3: Push images to Quay"
"${SCRIPT_DIR}/3-push-images.sh"

echo "==> Phase 4: Deploy with Helm"
"${SCRIPT_DIR}/4-deploy-helm.sh" --source "${SOURCE_DIR}"

echo "Done."
