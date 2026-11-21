#!/usr/bin/env bash
# Orchestrator — runs all Gitea deployment phases in order.
# Each phase script can also be run independently.
#
# Usage: ./deploy-gitea.sh --source <path-to-byop-broker>
#
# Required environment variables:
#   QUAY_REGISTRY      e.g. registry-quay-quay-enterprise.apps.<domain>
#   GITEA_ROBOT_TOKEN  robot account token (gitea+gitea_push)
#   CLUSTER_DOMAIN     e.g. apps.mycluster.example.com
#   GITEA_PASSWORD     admin password for the gitops user
#   GITEA_EMAIL        admin email for the gitops user
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
for tool in oc podman helm curl; do
  command -v "$tool" &>/dev/null || { echo "ERROR: $tool not found in PATH"; exit 1; }
done

# ---------------------------------------------------------------------------
# Validate environment variables — all phases combined
# ---------------------------------------------------------------------------
for var in QUAY_REGISTRY GITEA_ROBOT_TOKEN CLUSTER_DOMAIN GITEA_PASSWORD GITEA_EMAIL GITEA_SSH_KEY_PATH; do
  [[ -z "${!var:-}" ]] && echo "ERROR: $var is not set" && exit 1
done

[[ ! -f "${GITEA_SSH_KEY_PATH/#\~/$HOME}" ]]     && echo "ERROR: SSH private key not found: $GITEA_SSH_KEY_PATH" && exit 1
[[ ! -f "${GITEA_SSH_KEY_PATH/#\~/$HOME}.pub" ]] && echo "ERROR: SSH public key not found: ${GITEA_SSH_KEY_PATH}.pub" && exit 1

# ---------------------------------------------------------------------------
# Validate cluster connectivity
# ---------------------------------------------------------------------------
oc whoami &>/dev/null || { echo "ERROR: cannot connect to cluster — check kubeconfig"; exit 1; }

# ---------------------------------------------------------------------------
# Run phases
# ---------------------------------------------------------------------------
echo "==> Phase 1: Generate values file"
"${SCRIPT_DIR}/1-generate-values.sh" --source "${SOURCE_DIR}"

echo "==> Phase 2: Mirror images"
"${SCRIPT_DIR}/2-mirror-images.sh"

echo "==> Phase 3: Deploy with Helm"
"${SCRIPT_DIR}/3-deploy-helm.sh" --source "${SOURCE_DIR}"

echo "==> Phase 4: Create admin user"
"${SCRIPT_DIR}/4-create-admin-user.sh"

echo "==> Phase 5: Add SSH public key"
"${SCRIPT_DIR}/5-add-ssh-key.sh"

echo "==> Phase 6: Create gitops repository"
"${SCRIPT_DIR}/6-create-repo.sh"

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
"${SCRIPT_DIR}/show-gitea-outputs.sh"

echo "Done."
