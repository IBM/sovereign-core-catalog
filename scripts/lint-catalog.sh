#!/usr/bin/env bash
# lint-catalog.sh [-q|--quiet] [<path>]
#
# Validates every catalog item under components/ (or a given path) against
# the field contract that import.sh expects.
#
# import.sh reads from two files per product:
#
#   <product>/v*/metadata.yaml      — spec.catalog.{sourceType,name,sourceRepo,images[]}
#   <product>/catalog/catalog.yaml  — flat keys: display_name, description,
#                                     support_url, marketing_url, tags
#   <product>/catalog/schema.json   — must exist and be valid JSON
#
# NOTE — KNOWN SCHEMA MISMATCH (interim):
#   The existing catalog/catalog.yaml files use a nested structure:
#     spec.catalogRegistration.displayName / .description / .category /
#     .supportUrl / .marketingUrl / .tags
#   import.sh reads flat snake_case keys at the document root:
#     .display_name / .description / .category / .support_url / .marketing_url / .tags
#   These do not match. This linter validates the import.sh contract (flat keys),
#   so all existing catalog/catalog.yaml files currently FAIL. That is intentional —
#   this PR surfaces the breakage rather than hiding it. The schema mismatch must
#   be resolved in a follow-up PR by either:
#     (a) updating import.sh to read spec.catalogRegistration.* (nested, camelCase), or
#     (b) updating all catalog/catalog.yaml files to use flat snake_case root keys.
#
# A "catalog item" is any product directory that has both a catalog/ subdir
# and at least one v*.*.*/ version directory.
#
# Options:
#   -q, --quiet     Suppress passing lines; print only failures.
#   <path>          Directory to scan instead of the default components/.
#                   Can be a specific product root (e.g.
#                   components/software/open-source/redis) or any ancestor
#                   directory — all descendants are found recursively.
#
# Exit code: 0 = all OK, 1 = one or more failures.
#
# Requires: yq (mikefarah/yq v4), python3
#
# Invoked by: make lint-catalog (verbose), make lint (quiet)
# Paired with: scripts/validate-local.sh — validates v*/metadata.yaml and
#   profile.yaml against the catalog listing schema.
# If you change the field contract checked here (e.g. the keys read from
# catalog/catalog.yaml or v*/metadata.yaml), ensure validate-local.sh and
# the Makefile targets remain consistent.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
QUIET=false
CATALOG_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -q|--quiet) QUIET=true; shift ;;
    -*) echo "ERROR: unknown option: $1"; exit 1 ;;
    *)  CATALOG_ROOT="$1"; shift ;;
  esac
done

# Resolve the root: absolute, repo-relative, or default
if [[ -z "$CATALOG_ROOT" ]]; then
  CATALOG_ROOT="${REPO_ROOT}/components"
elif [[ "$CATALOG_ROOT" != /* ]]; then
  CATALOG_ROOT="${REPO_ROOT}/${CATALOG_ROOT}"
fi
CATALOG_ROOT="$(cd "$CATALOG_ROOT" 2>/dev/null && pwd)" \
  || { echo "ERROR: path not found: ${CATALOG_ROOT}"; exit 1; }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
ERRORS=0
CURRENT_ITEM_REL=""  # repo-relative path to the current product dir

fail() {
  local file="$1"; shift
  echo "FAIL ${CURRENT_ITEM_REL}/${file}: $*"
  ERRORS=$(( ERRORS + 1 ))
}

pass() {
  [[ "$QUIET" == "true" ]] && return
  local file="$1"; shift
  echo "ok   ${CURRENT_ITEM_REL}/${file}: $*"
}

require_yq() {
  command -v yq &>/dev/null || { echo "ERROR: yq (mikefarah/yq) not found in PATH"; exit 1; }
}

require_python3() {
  command -v python3 &>/dev/null || { echo "ERROR: python3 not found in PATH"; exit 1; }
}

# yq_get FILE PATH — returns the value or empty string; never errors
yq_get() {
  yq "$2" "$1" 2>/dev/null || echo ""
}

# ---------------------------------------------------------------------------
# Per-file checks
# ---------------------------------------------------------------------------

# Check the versioned metadata.yaml for a spec.catalog block.
# import.sh auto-selects the highest v*.*.*/ dir; we check all of them and
# require at least the latest one to be complete.
check_version_metadata() {
  local product_dir="$1"

  # Find all v*.*.*/ dirs, sorted, pick the latest
  local latest_version
  latest_version=$(find "$product_dir" -maxdepth 1 -type d -name 'v*.*.*' \
    -exec basename {} \; \
    | sort -t. -k1,1V -k2,2n -k3,3n 2>/dev/null \
    | tail -1)

  if [[ -z "$latest_version" ]]; then
    fail "v*.*.*/" "no version directory found"
    return
  fi

  local meta="${product_dir}/${latest_version}/metadata.yaml"
  local f="${latest_version}/metadata.yaml"

  if [[ ! -f "$meta" ]]; then
    fail "$f" "file missing"
    return
  fi

  local source_type; source_type=$(yq_get "$meta" '.spec.catalog.sourceType')
  local name;        name=$(yq_get "$meta" '.spec.catalog.name')
  local source_repo; source_repo=$(yq_get "$meta" '.spec.catalog.sourceRepo // ""')

  if [[ -z "$source_type" || "$source_type" == "null" ]]; then
    fail "$f" ".spec.catalog.sourceType is missing or null"
  elif [[ "$source_type" != "helm-registry" && "$source_type" != "helm-git" ]]; then
    fail "$f" ".spec.catalog.sourceType='${source_type}' must be helm-registry or helm-git"
  else
    pass "$f" ".spec.catalog.sourceType=${source_type}"
  fi

  if [[ -z "$name" || "$name" == "null" ]]; then
    fail "$f" ".spec.catalog.name is missing or null"
  else
    pass "$f" ".spec.catalog.name=${name}"
  fi

  # helm-git without a bundled chart/ dir requires .spec.catalog.sourcePath
  if [[ "$source_type" == "helm-git" && ! -d "${product_dir}/chart" ]]; then
    local source_path; source_path=$(yq_get "$meta" '.spec.catalog.sourcePath // ""')
    if [[ -z "$source_path" || "$source_path" == "null" ]]; then
      fail "$f" "sourceType=helm-git with no bundled chart/ requires .spec.catalog.sourcePath"
    else
      pass "$f" ".spec.catalog.sourcePath=${source_path}"
    fi
  fi

  # helm-registry and helm-git (remote) both require .spec.catalog.sourceRepo
  if [[ "$source_type" == "helm-registry" ]] || \
     [[ "$source_type" == "helm-git" && ! -d "${product_dir}/chart" ]]; then
    if [[ -z "$source_repo" || "$source_repo" == "null" ]]; then
      fail "$f" ".spec.catalog.sourceRepo is missing or null (required for sourceType=${source_type})"
    else
      pass "$f" ".spec.catalog.sourceRepo=${source_repo}"
    fi
  fi

  local image_count; image_count=$(yq_get "$meta" '.spec.catalog.images | length')
  if [[ -z "$image_count" || "$image_count" == "null" || "$image_count" == "0" ]]; then
    fail "$f" ".spec.catalog.images array is missing or empty"
  else
    pass "$f" ".spec.catalog.images has ${image_count} entries"
    local idx=0
    while (( idx < image_count )); do
      local src; src=$(yq_get "$meta" ".spec.catalog.images[${idx}].source")
      local dst; dst=$(yq_get "$meta" ".spec.catalog.images[${idx}].destination")
      [[ -z "$src" || "$src" == "null" ]] && fail "$f" ".spec.catalog.images[${idx}].source is missing or null"
      [[ -z "$dst" || "$dst" == "null" ]] && fail "$f" ".spec.catalog.images[${idx}].destination is missing or null"
      idx=$(( idx + 1 ))
    done
  fi
}

check_catalog() {
  local catalog="$1"
  local f="catalog/catalog.yaml"

  if [[ ! -f "$catalog" ]]; then
    fail "$f" "file missing"
    return
  fi

  for key in display_name description support_url marketing_url; do
    local val; val=$(yq_get "$catalog" ".${key}")
    if [[ -z "$val" || "$val" == "null" ]]; then
      fail "$f" ".${key} is missing or null"
    else
      pass "$f" ".${key} present"
    fi
  done

  local tag_count; tag_count=$(yq_get "$catalog" '.tags | length')
  if [[ -z "$tag_count" || "$tag_count" == "null" || "$tag_count" == "0" ]]; then
    fail "$f" ".tags array is missing or empty"
  else
    pass "$f" ".tags has ${tag_count} entries"
  fi
}

check_schema() {
  local schema="$1"
  local f="catalog/schema.json"

  if [[ ! -f "$schema" ]]; then
    fail "$f" "file missing"
    return
  fi

  if [[ ! -s "$schema" ]]; then
    fail "$f" "file is empty"
    return
  fi

  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$schema" 2>/dev/null \
    && pass "$f" "valid JSON" \
    || fail "$f" "not valid JSON"
}

# ---------------------------------------------------------------------------
# Main loop — find all product dirs that have a catalog/ subdir
# ---------------------------------------------------------------------------
require_yq
require_python3

echo ""
echo "Validating catalog import contract (v*/metadata.yaml, catalog/catalog.yaml, catalog/schema.json) under ${CATALOG_ROOT#${REPO_ROOT}/}"

found=0
product_dirs=()

if [[ -d "${CATALOG_ROOT}/catalog" ]]; then
  product_dirs=("$CATALOG_ROOT")
else
  while IFS= read -r d; do
    product_dirs+=("$d")
  done < <(
    find "$CATALOG_ROOT" -mindepth 1 -type d -name catalog \
      | sed 's|/catalog$||' \
      | sort
  )
fi

for product_dir in "${product_dirs[@]}"; do
  [[ -d "${product_dir}/catalog" ]] || continue
  CURRENT_ITEM_REL="${product_dir#${REPO_ROOT}/}"
  found=$(( found + 1 ))
  check_version_metadata "$product_dir"
  check_catalog  "${product_dir}/catalog/catalog.yaml"
  check_schema   "${product_dir}/catalog/schema.json"
done

echo ""
if [[ "$found" == "0" ]]; then
  echo "WARNING: no catalog items found under ${CATALOG_ROOT#${REPO_ROOT}/}"
  exit 0
fi

if [[ "$ERRORS" -gt 0 ]]; then
  echo "FAILED: catalog import contract validation found ${ERRORS} error(s) across ${found} item(s)."
  exit 1
else
  echo "OK: all ${found} catalog item(s) passed."
fi
