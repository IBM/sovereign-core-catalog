#!/usr/bin/env bash
# Sovereign Store — Local Structural Smoke Test
# Pre-PR local check for metadata files. Full schema validation runs in CI.
#
# Invoked by: make validate-local (verbose), make lint (quiet)
# Paired with: scripts/lint-catalog.sh — validates catalog/catalog.yaml and
#   v*/metadata.yaml spec.catalog.* fields (import.sh contract).
# If you change the field contract checked here, ensure lint-catalog.sh and
# the Makefile targets remain consistent.
#
# Options:
#   -q, --quiet   Suppress per-file progress lines; print only failures and
#                 the final status line.

set -euo pipefail

QUIET=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -q|--quiet) QUIET=true; shift ;;
    *) shift ;;
  esac
done

echo "Validating listing metadata (v*/metadata.yaml, profile.yaml) against catalog schema"

FOUND_ERRORS=0
CURRENT_FILE=""

# Checks if a given YAML key exists in the file
has_yaml_key() {
    local key="$1"
    local file="$2"
    grep -Eq "^[[:space:]]*${key}:" "$file"
}

# Checks if a YAML key is present but empty (e.g. '', "", null, ~, or blank with no child block)
is_yaml_key_empty() {
    local key="$1"
    local file="$2"

    local line_num
    line_num=$(grep -n -E "^[[:space:]]*${key}:" "$file" | head -n 1 | cut -d: -f1)
    [ -z "$line_num" ] && return 1

    local line
    line=$(sed -n "${line_num}p" "$file")

    # Extract scalar value after key
    local val
    val=$(echo "$line" | sed -E "s/^[[:space:]]*${key}:[[:space:]]*//" | sed -E 's/[[:space:]]+$//')

    # Case 1: Explicitly empty / null scalar values
    case "$val" in
        '""'|"''"|'null'|'~') return 0 ;;
    esac

    # Case 2: Non-empty inline value present
    [ -n "$val" ] && return 1

    # Case 3: Empty inline value — check if followed by indented child block / list item
    local next_line cur_indent
    next_line=$(sed -n "$((line_num + 1))p" "$file")
    cur_indent=$(echo "$line" | sed -E 's/^([[:space:]]*).*/\1/')

    # If next line has deeper indentation, it is a non-empty nested structure
    if echo "$next_line" | grep -Eq "^${cur_indent}[[:space:]]+"; then
        return 1
    fi

    return 0
}

# Extracts the scalar value for a given key, stripped of quotes and surrounding whitespace
get_yaml_scalar_value() {
    local key="$1"
    local file="$2"

    local line
    line=$(grep -E "^[[:space:]]*${key}:" "$file" | head -n 1 || true)
    [ -z "$line" ] && return 1

    local val
    val=$(echo "$line" | sed -E "s/^[[:space:]]*${key}:[[:space:]]*//" | sed -E 's/[[:space:]]+$//')
    # Strip surrounding single or double quotes
    val=$(echo "$val" | sed -E 's/^["'"'"'](.*)["'"'"']$/\1/')
    echo "$val"
}

# Extracts the scalar value for a key from a YAML file (same technique as is_yaml_key_empty)
get_yaml_value() {
    local key="$1"
    local file="$2"
    local line_num
    line_num=$(grep -n -E "^[[:space:]]*${key}:" "$file" | head -n 1 | cut -d: -f1)
    [ -z "$line_num" ] && return 0
    local line
    line=$(sed -n "${line_num}p" "$file")
    echo "$line" | sed -E "s/^[[:space:]]*${key}:[[:space:]]*//" | sed -E "s/^['\"]|['\"]$//g" | sed -E 's/[[:space:]]+$//'
}

# Checks that a field's value is one of the allowed enum values (pipe-separated, e.g. "USA|UK|France")
# No-op if the field is absent (presence is enforced separately by check_required_fields).
check_enum_field() {
    local key="$1"
    local file="$2"
    local allowed="$3"   # pipe-separated, e.g. "USA|UK|France"

    # Skip if the key is not present in this file
    if ! has_yaml_key "$key" "$file"; then
        return 0
    fi

    local val
    val=$(get_yaml_value "$key" "$file")

    # Skip if value is empty (emptiness already caught by check_required_fields)
    [ -z "$val" ] && return 0

    if ! echo "$val" | grep -Eq "^(${allowed})$"; then
        echo "FAIL ${CURRENT_FILE}: invalid value for '${key}': \"${val}\" — allowed: $(echo "$allowed" | tr '|' ' ')"
        FOUND_ERRORS=1
    fi
}

# Validates field values against predefined formats and naming conventions
validate_field_patterns() {
    local meta_file="$1"

    # apiVersion format
    if has_yaml_key "apiVersion" "$meta_file"; then
        local api_version
        api_version=$(get_yaml_scalar_value "apiVersion" "$meta_file")
        if [ -n "$api_version" ] && [ "$api_version" != "sovereign-catalog.io/v1alpha1" ]; then
            echo "FAIL ${meta_file}: invalid apiVersion '${api_version}' (expected: sovereign-catalog.io/v1alpha1)"
            FOUND_ERRORS=1
        fi
    fi

    # slug naming convention: lowercase letters, numbers, and hyphens (no leading/trailing hyphen)
    if has_yaml_key "slug" "$meta_file"; then
        local slug
        slug=$(get_yaml_scalar_value "slug" "$meta_file")
        if [ -n "$slug" ] && ! echo "$slug" | grep -Eq "^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$"; then
            echo "FAIL ${meta_file}: invalid slug '${slug}' (expected: lowercase alphanumeric and hyphens, e.g. 'nova-shield-tech')"
            FOUND_ERRORS=1
        fi
    fi

    # companyRef format: companies/<slug>
    if has_yaml_key "companyRef" "$meta_file"; then
        local company_ref
        company_ref=$(get_yaml_scalar_value "companyRef" "$meta_file")
        if [ -n "$company_ref" ] && ! echo "$company_ref" | grep -Eq "^companies/[a-z0-9][a-z0-9-]*[a-z0-9]$|^companies/[a-z0-9]$"; then
            echo "FAIL ${meta_file}: invalid companyRef '${company_ref}' (expected: 'companies/<slug>')"
            FOUND_ERRORS=1
        fi
    fi

    # lifecycleStatus enum
    if has_yaml_key "lifecycleStatus" "$meta_file"; then
        local lifecycle_status
        lifecycle_status=$(get_yaml_scalar_value "lifecycleStatus" "$meta_file")
        if [ -n "$lifecycle_status" ] && ! echo "$lifecycle_status" | grep -Eq "^(draft|review|approved|deprecated|retired)$"; then
            echo "FAIL ${meta_file}: invalid lifecycleStatus '${lifecycle_status}' (expected: draft|review|approved|deprecated|retired)"
            FOUND_ERRORS=1
        fi
    fi

    # storefrontVisibility enum
    if has_yaml_key "storefrontVisibility" "$meta_file"; then
        local storefront_vis
        storefront_vis=$(get_yaml_scalar_value "storefrontVisibility" "$meta_file")
        if [ -n "$storefront_vis" ] && ! echo "$storefront_vis" | grep -Eq "^(public|unlisted|private)$"; then
            echo "FAIL ${meta_file}: invalid storefrontVisibility '${storefront_vis}' (expected: public|unlisted|private)"
            FOUND_ERRORS=1
        fi
    fi

    # availabilityState enum
    if has_yaml_key "availabilityState" "$meta_file"; then
        local avail_state
        avail_state=$(get_yaml_scalar_value "availabilityState" "$meta_file")
        if [ -n "$avail_state" ] && ! echo "$avail_state" | grep -Eq "^(available_central_it|byop_ready|technical_assets_available|discoverable_only)$"; then
            echo "FAIL ${meta_file}: invalid availabilityState '${avail_state}' (expected: available_central_it|byop_ready|technical_assets_available|discoverable_only)"
            FOUND_ERRORS=1
        fi
    fi
}

# Validates required fields for a catalog entry kind
check_required_fields() {
    local meta_file="$1"
    local kind="$2"
    local fields=""

    case "$kind" in
        CompanyProfile)
            fields="apiVersion kind slug displayName corporateHQ website"
            ;;
        SoftwareListing)
            fields="apiVersion kind companyRef vendor product version shortDescription fullDescription sovereignCoreRelevance category industries intendedUsers availabilityState lifecycleStatus storefrontVisibility hq format airgapReady podSecurityStandard type repository"
            ;;
        HardwareProfile)
            fields="apiVersion kind companyRef vendor product shortDescription fullDescription sovereignCoreRelevance category industries intendedUsers availabilityState lifecycleStatus storefrontVisibility hq capabilities"
            ;;
        ModelListing)
            fields="apiVersion kind companyRef vendor product version shortDescription fullDescription sovereignCoreRelevance category industries intendedUsers availabilityState lifecycleStatus storefrontVisibility enabled license hq format weightsRepository servingEngine"
            ;;
        ServiceProfile)
            fields="apiVersion kind companyRef name shortDescription fullDescription sovereignCoreRelevance industries intendedUsers availabilityState lifecycleStatus storefrontVisibility serviceType corporateHQ"
            ;;
        SovereignCoreHelmMapping)
            fields="apiVersion kind"
            ;;
        *)
            echo "WARN ${meta_file}: unknown kind '${kind}'"
            FOUND_ERRORS=1
            return
            ;;
    esac

    # Open-source community listings do not declare a vendor HQ
    if echo "$meta_file" | grep -q "/open-source/"; then
        fields="${fields// hq/}"
    fi

    for field in $fields; do
        if ! has_yaml_key "$field" "$meta_file"; then
            echo "FAIL ${meta_file}: missing required field '${field}'"
            FOUND_ERRORS=1
        elif [ "$field" != "capabilities" ] && is_yaml_key_empty "$field" "$meta_file"; then
            echo "FAIL ${meta_file}: required field '${field}' is present but empty"
            FOUND_ERRORS=1
        fi
    done

    # Enum checks — mirror the constraints added to the five JSON schemas.
    # The open-source pseudo-company profile uses "Global" (no single-country HQ)
    # and is intentionally exempt, consistent with the open-source component exemption above.
    if echo "$meta_file" | grep -q "/open-source/"; then
        return 0
    fi
    local hq_enum="USA|UK|France|Germany|India|Canada|Australia|Japan"
    case "$kind" in
        ModelListing|SoftwareListing|HardwareProfile)
            check_enum_field "hq"                      "$meta_file" "$hq_enum"
            check_enum_field "ultimateParentCompanyHQ"  "$meta_file" "$hq_enum"
            ;;
        ServiceProfile|CompanyProfile)
            check_enum_field "corporateHQ"              "$meta_file" "$hq_enum"
            check_enum_field "ultimateParentCompanyHQ"  "$meta_file" "$hq_enum"
            ;;
    esac
}

# Locate all metadata & profile YAML files in components and companies
while IFS= read -r meta_file; do
    [ -z "$meta_file" ] && continue
    CURRENT_FILE="$meta_file"
    [[ "$QUIET" == "false" ]] && echo "ok   ${meta_file}: checking"

    if ! has_yaml_key "kind" "$meta_file"; then
        echo "FAIL ${meta_file}: missing required field 'kind'"
        FOUND_ERRORS=1
        continue
    fi

    kind=$(grep -E '^[[:space:]]*kind:' "$meta_file" | head -n 1 | cut -d: -f2- | tr -d ' "' | tr -d '\t')
    check_required_fields "$meta_file" "$kind"
    validate_field_patterns "$meta_file"
done < <(find components companies \( -name "profile.yaml" -o \( -name "metadata.yaml" -not -path "*/open-source/*" \) -o -path "*/open-source/*/v*/metadata.yaml" \) -print 2>/dev/null)

if [ "$FOUND_ERRORS" -eq 1 ]; then
    echo ""
    echo "FAILED: listing metadata validation found errors."
    exit 1
fi

echo ""
echo "OK: all listing metadata files passed."
exit 0
