#!/usr/bin/env bash
# Show the runtime values needed by downstream deployments (ArgoCD, broker).
# Can be run any time after Gitea is deployed.
#
# Prints GITEA_HOST, GITEA_SSH_PORT, GITEA_USER_ID and GITEA_ROUTE_HOST to stdout.

set -euo pipefail

command -v oc &>/dev/null || { echo "ERROR: oc not found in PATH"; exit 1; }
oc whoami &>/dev/null || { echo "ERROR: cannot connect to cluster — check kubeconfig"; exit 1; }

GITEA_POD=$(oc get pod -n gitea -l app.kubernetes.io/name=gitea -o jsonpath='{.items[0].metadata.name}')
[[ -z "$GITEA_POD" ]] && echo "ERROR: no Gitea pod found in namespace gitea" && exit 1

GITEA_HOST=$(oc get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
GITEA_SSH_PORT=$(oc get svc -n gitea -o jsonpath='{.items[?(@.spec.ports[0].name=="ssh")].spec.ports[0].nodePort}')
GITEA_USER_ID=$(oc exec -n gitea "${GITEA_POD}" -- id -u)
GITEA_ROUTE_HOST=$(oc get route -n gitea -l app.kubernetes.io/name=gitea -o jsonpath='{.items[0].spec.host}')

[[ -z "$GITEA_HOST" ]]       && echo "ERROR: could not resolve GITEA_HOST — is a node available?" && exit 1
[[ -z "$GITEA_SSH_PORT" ]]   && echo "ERROR: could not resolve GITEA_SSH_PORT — is the Gitea SSH service ready?" && exit 1
[[ -z "$GITEA_USER_ID" ]]    && echo "ERROR: could not resolve GITEA_USER_ID — is the Gitea pod running?" && exit 1
[[ -z "$GITEA_ROUTE_HOST" ]] && echo "ERROR: could not resolve GITEA_ROUTE_HOST — is the Gitea route created?" && exit 1

echo "export GITEA_HOST=${GITEA_HOST}"
echo "export GITEA_SSH_PORT=${GITEA_SSH_PORT}"
echo "export GITEA_USER_ID=${GITEA_USER_ID}"
echo "export GITEA_ROUTE_HOST=${GITEA_ROUTE_HOST}"
