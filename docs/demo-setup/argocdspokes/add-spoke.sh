#!/usr/bin/env bash
# Register a spoke cluster with a hub ArgoCD instance.
#
# Usage: ./add-spoke.sh --hub-context <ctx> --spoke-context <ctx> [OPTIONS]
#
# Options:
#   --hub-context CONTEXT    Hub cluster kubeconfig context (required)
#   --spoke-context CONTEXT  Spoke cluster kubeconfig context (required)
#   --namespace NAMESPACE    ArgoCD namespace on hub (default: argocd)
#   --spoke-name NAME        Friendly name for spoke (default: context name)
#   --force-insecure         Force an insecure connection to the spoke
#   --list                   List current cluster registrations then exit
#   --dry-run                Show what would be done without making changes
#   -h, --help               Show this help message

set -euo pipefail

HUB_CONTEXT=""
SPOKE_CONTEXT=""
NAMESPACE="argocd"
SPOKE_NAME=""
DRY_RUN=false
LIST=false
FORCE_INSECURE=false

hub_oc() { oc --context="${HUB_CONTEXT}" "$@"; }
spoke_oc() { oc --context="${SPOKE_CONTEXT}" "$@"; }

show_help() {
  cat <<EOF
Usage: $0 --hub-context <ctx> --spoke-context <ctx> [OPTIONS]

Register a spoke cluster with a hub ArgoCD instance.

Options:
  --hub-context CONTEXT    Hub cluster kubeconfig context (required)
  --spoke-context CONTEXT  Spoke cluster kubeconfig context (required)
  --namespace NAMESPACE    ArgoCD namespace on hub (default: argocd)
  --spoke-name NAME        Friendly name for spoke (default: context name)
  --force-insecure         Force an insecure connection to the spoke
  --list                   List current cluster registrations then exit
  --dry-run                Show what would be done without making changes
  -h, --help               Show this help message

Examples:
  $0 --hub-context hub --list
  $0 --hub-context hub --spoke-context spoke-1 --dry-run
  $0 --hub-context hub --spoke-context spoke-1
  $0 --hub-context hub --spoke-context spoke-1 --spoke-name "Production East" --namespace gitops
EOF
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --hub-context)   HUB_CONTEXT="$2";   shift 2 ;;
    --spoke-context) SPOKE_CONTEXT="$2"; shift 2 ;;
    --namespace)     NAMESPACE="$2";     shift 2 ;;
    --spoke-name)    SPOKE_NAME="$2";    shift 2 ;;
    --force-insecure) FORCE_INSECURE=true; shift   ;;
    --list)          LIST=true;          shift   ;;
    --dry-run)       DRY_RUN=true;       shift   ;;
    -h|--help)       show_help; exit 0           ;;
    *) echo "ERROR: unknown option: $1"; echo ""; show_help; exit 1 ;;
  esac
done

command -v oc &>/dev/null || { echo "ERROR: oc not found in PATH"; exit 1; }

[[ -z "$HUB_CONTEXT" ]] && { echo "ERROR: --hub-context is required"; echo ""; show_help; exit 1; }
[[ "$LIST" = false && -z "$SPOKE_CONTEXT" ]] && { echo "ERROR: --spoke-context is required"; echo ""; show_help; exit 1; }

[[ -z "$SPOKE_NAME" && -n "$SPOKE_CONTEXT" ]] && SPOKE_NAME="$SPOKE_CONTEXT"

oc config get-contexts "${HUB_CONTEXT}" &>/dev/null || {
  echo "ERROR: hub context '${HUB_CONTEXT}' not found in kubeconfig"
  echo "Available contexts:"; oc config get-contexts; exit 1
}
hub_oc whoami &>/dev/null || { echo "ERROR: cannot connect to hub cluster '${HUB_CONTEXT}' — check kubeconfig"; exit 1; }

if [[ "$LIST" = true ]]; then
  hub_oc get secrets -n "${NAMESPACE}" -l argocd.argoproj.io/secret-type=cluster
  exit 0
fi

oc config get-contexts "${SPOKE_CONTEXT}" &>/dev/null || {
  echo "ERROR: spoke context '${SPOKE_CONTEXT}' not found in kubeconfig"
  echo "Available contexts:"; oc config get-contexts; exit 1
}
spoke_oc whoami &>/dev/null || { echo "ERROR: cannot connect to spoke cluster '${SPOKE_CONTEXT}' — check kubeconfig"; exit 1; }

hub_oc get namespace "${NAMESPACE}" &>/dev/null || {
  echo "ERROR: namespace '${NAMESPACE}' not found on hub cluster — is ArgoCD installed?"
  exit 1
}

if [[ "$DRY_RUN" = true ]]; then
  SECRET_NAME_PREVIEW="cluster-$(echo "${SPOKE_NAME}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')"
  echo "hub-context:   ${HUB_CONTEXT}"
  echo "spoke-context: ${SPOKE_CONTEXT}"
  echo "spoke-name:    ${SPOKE_NAME}"
  echo "namespace:     ${NAMESPACE}"
  echo "force-insecure: ${FORCE_INSECURE}"
  echo "secret-name:   ${SECRET_NAME_PREVIEW}"
  echo ""
  echo "Would perform:"
  echo "  1. Extract spoke server URL and CA from kubeconfig"
  echo "  2. Create namespace '${NAMESPACE}' on spoke (idempotent)"
  echo "  3. Create argocd-manager ServiceAccount + token Secret + ClusterRole + ClusterRoleBinding on spoke (idempotent)"
  echo "  4. Wait for token (max 30 attempts x 2s)"
  echo "  5. Create cluster Secret '${SECRET_NAME_PREVIEW}' in namespace '${NAMESPACE}' on hub (idempotent)"
  echo "  6. Verify secret exists"
  echo "[add-spoke] Dry run complete — no changes made"
  exit 0
fi

# Step 1: Extract spoke server URL and CA
SPOKE_SERVER=$(spoke_oc config view --minify -o jsonpath='{.clusters[0].cluster.server}')

if [[ "$FORCE_INSECURE" = true ]]; then
  echo "WARNING: --force-insecure set — skipping CA extraction, using insecure connection (not recommended for production)"
  USE_INSECURE=true
else
  SPOKE_CA=$(spoke_oc config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' 2>/dev/null || true)

  if [[ -z "$SPOKE_CA" ]]; then
    SPOKE_CA=$(spoke_oc get configmap kube-root-ca.crt -n kube-system \
      -o jsonpath='{.data.ca\.crt}' 2>/dev/null | base64 | tr -d '\n' || true)
  fi

  if [[ -z "$SPOKE_CA" ]]; then
    echo "WARNING: could not extract CA certificate — using insecure connection (not recommended for production)"
    USE_INSECURE=true
  else
    USE_INSECURE=false
  fi
fi

# Step 2 & 3: Namespace + RBAC on spoke (idempotent via apply)
cat <<EOF | spoke_oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-manager
  namespace: ${NAMESPACE}
---
apiVersion: v1
kind: Secret
metadata:
  name: argocd-manager-token
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/service-account.name: argocd-manager
type: kubernetes.io/service-account-token
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-manager-role
rules:
- apiGroups: ['*']
  resources: ['*']
  verbs: ['*']
- nonResourceURLs: ['*']
  verbs: ['*']
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-manager-role-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: argocd-manager-role
subjects:
- kind: ServiceAccount
  name: argocd-manager
  namespace: ${NAMESPACE}
EOF

# Step 4: Wait for token
MAX_RETRIES=30
RETRY_COUNT=0
TOKEN=""

while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
  TOKEN=$(spoke_oc -n "${NAMESPACE}" get secret argocd-manager-token \
    -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || true)
  [[ -n "$TOKEN" ]] && break
  RETRY_COUNT=$((RETRY_COUNT + 1))
  echo "Waiting for token... (attempt ${RETRY_COUNT}/${MAX_RETRIES})"
  sleep 2
done

[[ -z "$TOKEN" ]] && {
  echo "ERROR: failed to retrieve service account token after ${MAX_RETRIES} attempts"
  echo "  Check: oc --context=${SPOKE_CONTEXT} -n ${NAMESPACE} get secret argocd-manager-token"
  exit 1
}

# Step 5: Create cluster Secret on hub (idempotent via apply)
SECRET_NAME="cluster-$(echo "${SPOKE_NAME}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')"

if [[ "$USE_INSECURE" = true ]]; then
  TLS_CONFIG='"tlsClientConfig": {"insecure": true}'
else
  TLS_CONFIG='"tlsClientConfig": {"insecure": false, "caData": "'"${SPOKE_CA}"'"}'
fi

cat <<EOF | hub_oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: ${SPOKE_NAME}
  server: "${SPOKE_SERVER}"
  config: |
    {"bearerToken": "${TOKEN}", ${TLS_CONFIG}}
EOF

# Step 6: Verify
hub_oc -n "${NAMESPACE}" get secret "${SECRET_NAME}" &>/dev/null || {
  echo "ERROR: cluster secret '${SECRET_NAME}' not found — registration may have failed"
  exit 1
}

echo ""
echo "Spoke '${SPOKE_NAME}' registered successfully"
echo "  secret:  ${SECRET_NAME}"
echo "  server:  ${SPOKE_SERVER}"
echo "  hub:     ${HUB_CONTEXT} / ${NAMESPACE}"
echo ""
echo "Verify:"
echo "  oc --context=${HUB_CONTEXT} -n ${NAMESPACE} get secrets -l argocd.argoproj.io/secret-type=cluster"
echo "  oc --context=${HUB_CONTEXT} -n ${NAMESPACE} get secret ${SECRET_NAME} -o yaml"
echo ""
echo "[add-spoke] Done."
