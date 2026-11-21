#!/usr/bin/env bash
# Show the runtime URLs for the BYOP broker deployment.
# Can be run any time after the broker is deployed.
#
# Prints BROKER_ROUTE_HOST and CATALOG_APP_ROUTE_HOST to stdout.

set -euo pipefail

command -v oc &>/dev/null || { echo "ERROR: oc not found in PATH"; exit 1; }
oc whoami &>/dev/null || { echo "ERROR: cannot connect to cluster — check kubeconfig"; exit 1; }

BROKER_ROUTE_HOST=$(oc get route byop-broker -n byop -o jsonpath='{.spec.host}')
CATALOG_APP_ROUTE_HOST=$(oc get route byop-catalog-app -n byop -o jsonpath='{.spec.host}')

echo "BROKER_ROUTE_HOST=${BROKER_ROUTE_HOST}"
echo "CATALOG_APP_ROUTE_HOST=${CATALOG_APP_ROUTE_HOST}"
