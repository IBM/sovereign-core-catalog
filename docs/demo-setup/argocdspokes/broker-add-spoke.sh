#!/usr/bin/env bash
# Add a spoke cluster entry to the broker values-generated.yaml and redeploy.
#
# Usage: ./broker-add-spoke.sh --source <path-to-byop-broker> --spoke-context <ctx> [OPTIONS]
#
# Options:
#   --source PATH          Path to byop-broker source directory (required)
#   --spoke-context CTX    Kubeconfig context to extract the spoke server URL (required)
#   --spoke-name NAME      Friendly name for spoke in broker config (default: context name)
#   --dry-run              Show changes without applying them
#   -h, --help             Show this help message
#
# The spoke server URL is extracted from the kubeconfig context.
# The values-generated.yaml is updated in place, then helm upgrade is run.

set -euo pipefail

SOURCE_DIR=""
SPOKE_CONTEXT=""
SPOKE_NAME=""
DRY_RUN=false

show_help() {
  cat <<EOF
Usage: $0 --source <path> --spoke-context <ctx> [OPTIONS]

Add a spoke cluster entry to the broker values-generated.yaml and redeploy.

Options:
  --source PATH          Path to byop-broker source directory (required)
  --spoke-context CTX    Kubeconfig context to extract the spoke server URL (required)
  --spoke-name NAME      Friendly name for spoke in broker config (default: context name)
  --dry-run              Show changes without applying them
  -h, --help             Show this help message

Examples:
  $0 --source ./archive/byop-broker --spoke-context spoke-1
  $0 --source ./archive/byop-broker --spoke-context spoke-1 --spoke-name "Production East"
  $0 --source ./archive/byop-broker --spoke-context spoke-1 --dry-run
EOF
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --source)        SOURCE_DIR="$2";    shift 2 ;;
    --spoke-context) SPOKE_CONTEXT="$2"; shift 2 ;;
    --spoke-name)    SPOKE_NAME="$2";    shift 2 ;;
    --dry-run)       DRY_RUN=true;       shift   ;;
    -h|--help)       show_help; exit 0           ;;
    *) echo "ERROR: unknown option: $1"; echo ""; show_help; exit 1 ;;
  esac
done

[[ -z "$SOURCE_DIR" ]]    && { echo "ERROR: --source is required"; echo ""; show_help; exit 1; }
[[ -z "$SPOKE_CONTEXT" ]] && { echo "ERROR: --spoke-context is required"; echo ""; show_help; exit 1; }

[[ -z "$SPOKE_NAME" ]] && SPOKE_NAME="$SPOKE_CONTEXT"

VALUES_FILE="${SOURCE_DIR}/values-generated.yaml"
[[ ! -f "$VALUES_FILE" ]] && echo "ERROR: values file not found: $VALUES_FILE — run broker/1-generate-values.sh first" && exit 1

for tool in oc helm python3; do
  command -v "$tool" &>/dev/null || { echo "ERROR: $tool not found in PATH"; exit 1; }
done

oc whoami &>/dev/null || { echo "ERROR: cannot connect to hub cluster — check kubeconfig"; exit 1; }

oc config get-contexts "${SPOKE_CONTEXT}" &>/dev/null || {
  echo "ERROR: spoke context '${SPOKE_CONTEXT}' not found in kubeconfig"
  echo "Available contexts:"; oc config get-contexts; exit 1
}

# Extract spoke server URL from kubeconfig
SPOKE_SERVER=$(oc --context="${SPOKE_CONTEXT}" config view --minify \
  -o jsonpath='{.clusters[0].cluster.server}')
[[ -z "$SPOKE_SERVER" ]] && echo "ERROR: could not extract server URL from context '${SPOKE_CONTEXT}'" && exit 1

# Check if this server or name is already in the values file
if python3 - "${VALUES_FILE}" "${SPOKE_SERVER}" "${SPOKE_NAME}" <<'PYEOF'
import sys, yaml
with open(sys.argv[1]) as f:
    v = yaml.safe_load(f)
clusters = v.get('broker', {}).get('clusters', [])
server = sys.argv[2]
name = sys.argv[3]
for c in clusters:
    if c.get('server') == server:
        print(f"already-server")
        sys.exit(0)
    if c.get('name') == name:
        print(f"already-name")
        sys.exit(0)
PYEOF
then
  ALREADY=$(python3 - "${VALUES_FILE}" "${SPOKE_SERVER}" "${SPOKE_NAME}" <<'PYEOF'
import sys, yaml
with open(sys.argv[1]) as f:
    v = yaml.safe_load(f)
clusters = v.get('broker', {}).get('clusters', [])
for c in clusters:
    if c.get('server') == sys.argv[2]:
        print("already-server"); sys.exit(0)
    if c.get('name') == sys.argv[3]:
        print("already-name"); sys.exit(0)
print("ok")
PYEOF
)
  if [[ "$ALREADY" == "already-server" ]]; then
    echo "ERROR: a cluster with server '${SPOKE_SERVER}' is already in the broker clusters list"
    exit 1
  fi
  if [[ "$ALREADY" == "already-name" ]]; then
    echo "ERROR: a cluster named '${SPOKE_NAME}' is already in the broker clusters list"
    exit 1
  fi
fi

echo "spoke-context: ${SPOKE_CONTEXT}"
echo "spoke-name:    ${SPOKE_NAME}"
echo "spoke-server:  ${SPOKE_SERVER}"
echo "values-file:   ${VALUES_FILE}"
echo ""

if [[ "$DRY_RUN" = true ]]; then
  echo "Would add to broker clusters:"
  echo "  - server: \"${SPOKE_SERVER}\""
  echo "    name: \"${SPOKE_NAME}\""
  echo "    type: spoke"
  echo ""
  echo "[broker-add-spoke] Dry run complete — no changes made."
  exit 0
fi

# Append spoke entry to broker.clusters in values-generated.yaml
python3 - "${VALUES_FILE}" "${SPOKE_SERVER}" "${SPOKE_NAME}" <<'PYEOF'
import sys, yaml

path, server, name = sys.argv[1], sys.argv[2], sys.argv[3]

with open(path) as f:
    v = yaml.safe_load(f)

v.setdefault('broker', {}).setdefault('clusters', []).append({
    'server': server,
    'name': name,
    'type': 'spoke',
})

with open(path, 'w') as f:
    yaml.dump(v, f, default_flow_style=False, allow_unicode=True)
PYEOF

echo "Added '${SPOKE_NAME}' to broker clusters list."
echo ""

# Redeploy broker with updated values
cd "${SOURCE_DIR}"
helm upgrade --install byop ./chart \
  --namespace byop \
  --create-namespace \
  --values "${VALUES_FILE}"

oc rollout status deployment/byop-broker -n byop --timeout=5m

echo ""
echo "Verify:"
echo "  oc exec -n byop deployment/byop-broker -- env | grep CLUSTERS"
echo ""
echo "[broker-add-spoke] Done."
