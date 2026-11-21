#!/usr/bin/env bash
# Phase 2 — Deploy QuayRegistry CR and wait for Quay to be available.
#
# Applies QuayRegistry named 'quay' in namespace 'quay-enterprise'
# with managed components (clair, postgres, objectstorage, redis,
# horizontalpodautoscaler, route, mirror) and unmanaged components
# (monitoring, tls).
#
# Polls status.conditions[?(@.type=="Available")].status == "True"
# every 10s up to 10 minutes.

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
# Step 1: Ensure config bundle secret exists
# ---------------------------------------------------------------------------
log_info "Ensuring registry-config-bundle secret exists..."
oc create secret generic registry-config-bundle \
  --from-literal=config.yaml="FEATURE_USER_CREATION: true" \
  -n quay-enterprise \
  --dry-run=client -o yaml | oc apply -f -
log_success "Config bundle secret ready"

# ---------------------------------------------------------------------------
# Step 2: Apply QuayRegistry CR
# ---------------------------------------------------------------------------
log_info "Creating QuayRegistry in namespace 'quay-enterprise'..."

oc apply -f - <<EOF
---
apiVersion: quay.redhat.com/v1
kind: QuayRegistry
metadata:
  name: registry
  namespace: quay-enterprise
spec:
  configBundleSecret: registry-config-bundle
  components:
    - kind: quay
      managed: true
      overrides:
        resources:
          limits:
            cpu: 4
    - kind: clair
      managed: true
    - kind: postgres
      managed: true
    - kind: objectstorage
      managed: true
    - kind: redis
      managed: true
    - kind: horizontalpodautoscaler
      managed: true
    - kind: route
      managed: true
    - kind: mirror
      managed: true
    - kind: monitoring
      managed: false
    - kind: tls
      managed: true
EOF

log_success "QuayRegistry created"

# ---------------------------------------------------------------------------
# Step 3: Wait for Quay to be ready
# ---------------------------------------------------------------------------
log_info "Waiting for Quay deployment (this may take several minutes)..."
log_info "Quay needs to initialize database, storage, and other components"

QUAY_READY=false
for i in {1..60}; do
  STATUS=$(oc get quayregistry registry -n quay-enterprise \
    -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "")

  if [ "$STATUS" = "True" ]; then
    QUAY_READY=true
    log_success "Quay is ready!"
    break
  fi

  if [ $((i % 10)) -eq 0 ]; then
    log_info "Still waiting... ($i/60)"
  fi

  sleep 10
done

if [ "$QUAY_READY" = false ]; then
  log_warning "Timeout waiting for Quay"
  log_info "Checking Quay status..."
  oc get quayregistry registry -n quay-enterprise || true
  echo ""
  oc get pods -n quay-enterprise || true
  echo ""
  log_warning "Quay may still be initializing. Check status above."
fi

# ---------------------------------------------------------------------------
# Step 4: Print registry endpoint
# ---------------------------------------------------------------------------
QUAY_ENDPOINT=$(oc get quayregistry registry -n quay-enterprise \
  -o jsonpath='{.status.registryEndpoint}' 2>/dev/null || echo "")

if [ -n "$QUAY_ENDPOINT" ]; then
  log_info "Quay Registry Endpoint: ${QUAY_ENDPOINT}"
fi

echo "[2-deploy-registry] Done."
