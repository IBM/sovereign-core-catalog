#!/usr/bin/env bash
# Remove a spoke cluster entry from the broker values-generated.yaml and redeploy.
#
# Usage: ./broker-remove-spoke.sh --source <path-to-byop-broker> --spoke-name <name> [OPTIONS]
#
# Options:
#   --source PATH       Path to byop-broker source directory (required)
#   --spoke-name NAME   Name of the spoke cluster to remove (required)
#   --dry-run           Show changes without applying them
#   -h, --help          Show this help message
#
# The entry is matched by the 'name' field in the broker clusters list.
# The hub entry (type: hub) cannot be removed.

set -euo pipefail

SOURCE_DIR=""
SPOKE_NAME=""
DRY_RUN=false

show_help() {
  cat <<EOF
Usage: $0 --source <path> --spoke-name <name> [OPTIONS]

Remove a spoke cluster entry from the broker values-generated.yaml and redeploy.

Options:
  --source PATH       Path to byop-broker source directory (required)
  --spoke-name NAME   Name of the spoke cluster to remove (required)
  --dry-run           Show changes without applying them
  -h, --help          Show this help message

Examples:
  $0 --source ./archive/byop-broker --spoke-name spoke-1
  $0 --source ./archive/byop-broker --spoke-name "Production East" --dry-run

List current entries:
  python3 -c "import yaml; v=yaml.safe_load(open('values-generated.yaml')); [print(c) for c in v['broker']['clusters']]"
EOF
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --source)     SOURCE_DIR="$2";  shift 2 ;;
    --spoke-name) SPOKE_NAME="$2";  shift 2 ;;
    --dry-run)    DRY_RUN=true;     shift   ;;
    -h|--help)    show_help; exit 0         ;;
    *) echo "ERROR: unknown option: $1"; echo ""; show_help; exit 1 ;;
  esac
done

[[ -z "$SOURCE_DIR" ]]  && { echo "ERROR: --source is required"; echo ""; show_help; exit 1; }
[[ -z "$SPOKE_NAME" ]]  && { echo "ERROR: --spoke-name is required"; echo ""; show_help; exit 1; }

VALUES_FILE="${SOURCE_DIR}/values-generated.yaml"
[[ ! -f "$VALUES_FILE" ]] && echo "ERROR: values file not found: $VALUES_FILE — run broker/1-generate-values.sh first" && exit 1

for tool in helm oc python3; do
  command -v "$tool" &>/dev/null || { echo "ERROR: $tool not found in PATH"; exit 1; }
done

oc whoami &>/dev/null || { echo "ERROR: cannot connect to hub cluster — check kubeconfig"; exit 1; }

# Verify the entry exists and is not the hub
RESULT=$(python3 - "${VALUES_FILE}" "${SPOKE_NAME}" <<'PYEOF'
import sys, yaml
with open(sys.argv[1]) as f:
    v = yaml.safe_load(f)
clusters = v.get('broker', {}).get('clusters', [])
for c in clusters:
    if c.get('name') == sys.argv[2]:
        if c.get('type') == 'hub':
            print("is-hub")
        else:
            print(f"found:{c.get('server','')}")
        sys.exit(0)
print("not-found")
PYEOF
)

if [[ "$RESULT" == "not-found" ]]; then
  echo "ERROR: no cluster named '${SPOKE_NAME}' found in broker clusters list"
  echo ""
  echo "Current entries:"
  python3 - "${VALUES_FILE}" <<'PYEOF'
import sys, yaml
with open(sys.argv[1]) as f:
    v = yaml.safe_load(f)
for c in v.get('broker', {}).get('clusters', []):
    print(f"  - name: {c.get('name','(unnamed)')!r}  server: {c.get('server','')}  type: {c.get('type','')}")
PYEOF
  exit 1
fi

if [[ "$RESULT" == "is-hub" ]]; then
  echo "ERROR: '${SPOKE_NAME}' is the hub cluster — it cannot be removed"
  exit 1
fi

SPOKE_SERVER="${RESULT#found:}"

echo "spoke-name:    ${SPOKE_NAME}"
echo "spoke-server:  ${SPOKE_SERVER}"
echo "values-file:   ${VALUES_FILE}"
echo ""

if [[ "$DRY_RUN" = true ]]; then
  echo "Would remove from broker clusters:"
  echo "  - server: \"${SPOKE_SERVER}\""
  echo "    name: \"${SPOKE_NAME}\""
  echo ""
  echo "[broker-remove-spoke] Dry run complete — no changes made."
  exit 0
fi

# Remove the spoke entry from broker.clusters
python3 - "${VALUES_FILE}" "${SPOKE_NAME}" <<'PYEOF'
import sys, yaml

path, name = sys.argv[1], sys.argv[2]

with open(path) as f:
    v = yaml.safe_load(f)

clusters = v.get('broker', {}).get('clusters', [])
v['broker']['clusters'] = [c for c in clusters if c.get('name') != name]

with open(path, 'w') as f:
    yaml.dump(v, f, default_flow_style=False, allow_unicode=True)
PYEOF

echo "Removed '${SPOKE_NAME}' from broker clusters list."
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
echo "[broker-remove-spoke] Done."
