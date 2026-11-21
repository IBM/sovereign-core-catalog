#!/usr/bin/env bash
# Orchestrator — runs all Quay deployment phases in order.
# Each phase script can also be run independently.
#
# Usage: ./deploy-quay.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Validate tools — all phases combined
# ---------------------------------------------------------------------------
for tool in oc; do
  command -v "$tool" &>/dev/null || { echo "ERROR: $tool not found in PATH"; exit 1; }
done

# ---------------------------------------------------------------------------
# Validate cluster connectivity
# ---------------------------------------------------------------------------
oc whoami &>/dev/null || { echo "ERROR: cannot connect to cluster — check kubeconfig"; exit 1; }

# ---------------------------------------------------------------------------
# Run phases
# ---------------------------------------------------------------------------
echo "==> Phase 1: Install Quay Operator"
"${SCRIPT_DIR}/1-install-operator.sh"

echo "==> Phase 2: Deploy Quay Registry"
"${SCRIPT_DIR}/2-deploy-registry.sh"

echo "==> Outputs"
"${SCRIPT_DIR}/show-quay-outputs.sh"

echo "Done."
