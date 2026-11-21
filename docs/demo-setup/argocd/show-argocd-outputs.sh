#!/usr/bin/env bash
# Show the runtime values for the ArgoCD deployment.
# Can be run any time after ArgoCD is deployed.
#
# Prints ARGOCD_ROUTE_HOST and ARGOCD_ADMIN_PASSWORD to stdout.

set -euo pipefail

command -v oc &>/dev/null || { echo "ERROR: oc not found in PATH"; exit 1; }
oc whoami &>/dev/null || { echo "ERROR: cannot connect to cluster — check kubeconfig"; exit 1; }

ARGOCD_ROUTE_HOST=$(oc get route argocd-server -n argocd -o jsonpath='{.spec.host}')
ARGOCD_ADMIN_PASSWORD=$(oc get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)

echo "ARGOCD_ROUTE_HOST=${ARGOCD_ROUTE_HOST}"
echo "ARGOCD_ADMIN_PASSWORD=${ARGOCD_ADMIN_PASSWORD}"
