#!/usr/bin/env bash
# Show the runtime values for the Quay deployment.
# Can be run any time after Quay is deployed.
#
# Prints QUAY_REGISTRY to stdout.

set -euo pipefail

command -v oc &>/dev/null || { echo "ERROR: oc not found in PATH"; exit 1; }
oc whoami &>/dev/null || { echo "ERROR: cannot connect to cluster — check kubeconfig"; exit 1; }

QUAY_REGISTRY=$(oc get quayregistry registry -n quay-enterprise -o jsonpath='{.status.registryEndpoint}')
[[ -z "$QUAY_REGISTRY" ]] && echo "ERROR: Quay registry endpoint is not available yet — is the QuayRegistry CR ready?" && exit 1

echo "export QUAY_REGISTRY=${QUAY_REGISTRY}"
