#!/usr/bin/env bash
# Phase 1 -- Install Quay Operator via OLM.
#
# Creates namespace quay-enterprise and a Subscription in openshift-operators
# pointing at the built-in redhat-operators catalog. No custom CatalogSource
# is needed. openshift-operators already has an all-namespaces OperatorGroup.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
  echo -e "${RED}[✗]${NC} $1"
}

# ---------------------------------------------------------------------------
# Validate tools
# ---------------------------------------------------------------------------
command -v oc &>/dev/null || { log_error "oc not found in PATH"; exit 1; }

# ---------------------------------------------------------------------------
# Validate cluster connectivity
# ---------------------------------------------------------------------------
oc whoami &>/dev/null || { log_error "cannot connect to cluster — check kubeconfig"; exit 1; }

# ---------------------------------------------------------------------------
# Step 1: Create quay-enterprise namespace
# ---------------------------------------------------------------------------
log_info "Creating namespace quay-enterprise..."
oc create namespace quay-enterprise --dry-run=client -o yaml | oc apply -f -
log_success "Namespace ready"

# ---------------------------------------------------------------------------
# Step 2: Install Quay Operator via OLM
# ---------------------------------------------------------------------------
log_info "Applying Subscription..."

oc apply -f - <<EOF
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: quay-operator
  namespace: openshift-operators
spec:
  channel: stable-3.13
  name: quay-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

log_success "Operator resources created"

# ---------------------------------------------------------------------------
# Step 3: Wait for Quay Operator CSV to reach Succeeded
# ---------------------------------------------------------------------------
log_info "Waiting for Quay Operator CSV to reach Succeeded (up to 5 minutes)..."

CSV_READY=false
for i in $(seq 1 60); do
  CSV_PHASE=$(oc get csv -n openshift-operators \
    --no-headers -o custom-columns="NAME:.metadata.name,PHASE:.status.phase" 2>/dev/null \
    | grep quay-operator | awk '{print $2}' || echo "")

  if [ "$CSV_PHASE" = "Succeeded" ]; then
    CSV_READY=true
    log_success "Quay operator CSV is Succeeded"
    break
  fi

  if [ $(( i % 10 )) -eq 0 ]; then
    log_info "Still waiting for CSV... ($((i * 5))s elapsed, phase: ${CSV_PHASE:-pending})"
  fi

  sleep 5
done

if [ "$CSV_READY" = false ]; then
  log_error "Quay operator CSV did not reach Succeeded after 5 minutes"
  log_info "Subscription status:"
  oc get subscription quay-operator -n openshift-operators -o yaml | grep -A10 status || true
  echo ""
  log_info "CSV list:"
  oc get csv -n openshift-operators | grep quay || true
  exit 1
fi

echo "[1-install-operator] Done."
