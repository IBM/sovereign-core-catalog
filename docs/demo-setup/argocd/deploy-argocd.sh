#!/usr/bin/env bash
# Orchestrator — runs all ArgoCD deployment phases in order.
# Each phase script can also be run independently.
#
# Usage: ./deploy-argocd.sh --source <path-to-byop-broker>
#
# Required environment variables:
#   QUAY_REGISTRY      e.g. registry-quay-quay-enterprise.apps.<domain>
#   ARGOCD_ROBOT_TOKEN robot account token (argoproj+argocd_push)
#   GITEA_HOST         from show-gitea-outputs.sh
#   GITEA_SSH_PORT     from show-gitea-outputs.sh
#   GITEA_USER_ID      from show-gitea-outputs.sh
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
for tool in oc podman ssh-keyscan python3; do
  command -v "$tool" &>/dev/null || { echo "ERROR: $tool not found in PATH"; exit 1; }
done

# ---------------------------------------------------------------------------
# Validate environment variables — all phases combined
# ---------------------------------------------------------------------------
for var in QUAY_REGISTRY ARGOCD_ROBOT_TOKEN GITEA_HOST GITEA_SSH_PORT GITEA_USER_ID GITEA_SSH_KEY_PATH; do
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
echo "==> Phase 1: Mirror images"
"${SCRIPT_DIR}/1-mirror-images.sh"

echo "==> Phase 2: Install ArgoCD"
"${SCRIPT_DIR}/2-install-argocd.sh" --source "${SOURCE_DIR}"

echo "==> Phase 3: Configure Gitea repository"
"${SCRIPT_DIR}/3-configure-repo.sh" --source "${SOURCE_DIR}"

echo "==> Phase 4: Register Gitea SSH known hosts"
"${SCRIPT_DIR}/4-register-known-hosts.sh"

echo "==> Phase 5: Restart ArgoCD"
"${SCRIPT_DIR}/5-restart-argocd.sh"

echo "Done."
