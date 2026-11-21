#!/usr/bin/env bash
# Phase 2 — Extract service definitions from the archive into the repo.
#
# Usage: ./2-extract-content.sh --repo-dir <path>

set -euo pipefail

[[ $# -lt 2 || "$1" != "--repo-dir" ]] && echo "Usage: $0 --repo-dir <path>" && exit 1
REPO_DIR="$2"
[[ ! -d "$REPO_DIR" ]] && echo "ERROR: repo directory not found: $REPO_DIR" && exit 1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE="${SCRIPT_DIR}/../archive/sample.tar.gz"
[[ ! -f "$ARCHIVE" ]] && echo "ERROR: archive not found: $ARCHIVE" && exit 1

command -v tar &>/dev/null || { echo "ERROR: tar not found in PATH"; exit 1; }

tar -xzf "${ARCHIVE}" --strip-components=1 -C "${REPO_DIR}"

echo "[2-extract-content] Done."
