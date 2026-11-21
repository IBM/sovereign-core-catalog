#!/usr/bin/env bash
# Phase 4 — Write pull, push and render helper scripts into the repo.
#
# Usage: ./4-create-helper-scripts.sh --repo-dir <path>
#
# Required environment variables:
#   GITEA_HOST         from Gitea deployment
#   GITEA_SSH_PORT     from Gitea deployment
#   GITEA_USER_ID      from Gitea deployment
#   GITEA_SSH_KEY_PATH path to Ed25519 private key, e.g. ~/.ssh/gitea_ed25519

set -euo pipefail

[[ $# -lt 2 || "$1" != "--repo-dir" ]] && echo "Usage: $0 --repo-dir <path>" && exit 1
REPO_DIR="$2"
[[ ! -d "$REPO_DIR" ]] && echo "ERROR: repo directory not found: $REPO_DIR" && exit 1

for var in GITEA_HOST GITEA_SSH_PORT GITEA_USER_ID GITEA_SSH_KEY_PATH; do
  [[ -z "${!var:-}" ]] && echo "ERROR: $var is not set" && exit 1
done

[[ ! -f "${GITEA_SSH_KEY_PATH/#\~/$HOME}" ]] && echo "ERROR: SSH key not found: $GITEA_SSH_KEY_PATH" && exit 1

GITEA_SSH_URL="ssh://${GITEA_USER_ID}@${GITEA_HOST}:${GITEA_SSH_PORT}/gitops/gitops.git"
SSH_KEY="${GITEA_SSH_KEY_PATH/#\~/$HOME}"

cat > "${REPO_DIR}/pull" <<EOF
#!/usr/bin/env bash
GIT_SSH_COMMAND="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" git pull
EOF
chmod +x "${REPO_DIR}/pull"

cat > "${REPO_DIR}/push" <<EOF
#!/usr/bin/env bash
GIT_SSH_COMMAND="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" git push
EOF
chmod +x "${REPO_DIR}/push"

cat > "${REPO_DIR}/render" <<EOF
#!/usr/bin/env bash
./tools/service-render --images --applicationset services/"\$1" --mapping image-mapping.txt --force \\
  --argocd-namespace argocd --repo-url ${GITEA_SSH_URL}
if [ -d "services/\$1" ]; then
  (cd "services/\$1/.."; rm -f latest)
  version=\$(basename "\$1")
  (cd "services/\$1/.."; ln -s "\${version}.rendered" latest)
fi
EOF
chmod +x "${REPO_DIR}/render"

cat > "${REPO_DIR}/list" <<'EOF'
#!/usr/bin/env bash
./tools/service-list "$@"
EOF
chmod +x "${REPO_DIR}/list"

cat > "${REPO_DIR}/reginfo" <<'EOF'
#!/usr/bin/env bash
./tools/service-reginfo "$@"
EOF
chmod +x "${REPO_DIR}/reginfo"

echo "[4-create-helper-scripts] Written: pull, push, render, list, reginfo"
