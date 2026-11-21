#!/usr/bin/env bash
# Phase 5 — Restart ArgoCD server to pick up the updated known_hosts.

set -euo pipefail

command -v oc &>/dev/null || { echo "ERROR: oc not found in PATH"; exit 1; }
oc whoami &>/dev/null || { echo "ERROR: cannot connect to cluster — check kubeconfig"; exit 1; }

oc rollout restart deployment/argocd-server -n argocd
oc rollout status deployment/argocd-server -n argocd --timeout=5m

oc rollout restart deployment/argocd-repo-server -n argocd
oc rollout status deployment/argocd-repo-server -n argocd --timeout=5m

echo "[5-restart-argocd] Done."
