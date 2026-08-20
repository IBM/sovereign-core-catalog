#!/bin/bash
# Sovereign Store — Local Structural Smoke Test
# This is a quick pre-PR check. Full JSON Schema validation runs in CI.

echo "🚀 Starting Sovereign Store Structural Smoke Test..."

FOUND_ERRORS=0

for meta_file in $(find components companies \( -name "profile.yaml" -o \( -name "metadata.yaml" -not -path "*/open-source/*" \) -o -path "*/open-source/*/v*/metadata.yaml" \) 2>/dev/null); do
    echo "🔍 Checking file: $meta_file"

    if ! grep -q "apiVersion:" "$meta_file"; then
        echo "  ❌ missing required field: apiVersion"
        FOUND_ERRORS=1
    fi

    if ! grep -q "kind:" "$meta_file"; then
        echo "  ❌ missing required field: kind"
        FOUND_ERRORS=1
    fi

    # SovereignCoreHelmMapping files declare jurisdiction by reference (companyRef),
    # not by an inline hq/corporateHQ field — skip that check for this kind.
    # Open-source community listings have no single vendor HQ, so they are
    # exempt from the hq/corporateHQ requirement as well.
    if ! grep -q "SovereignCoreHelmMapping" "$meta_file" && ! echo "$meta_file" | grep -q "/open-source/"; then
        if ! grep -q "hq:" "$meta_file" && ! grep -q "corporateHQ:" "$meta_file"; then
            echo "  ❌ missing required field: hq / corporateHQ"
            FOUND_ERRORS=1
        fi
    fi

    # All component entries must carry a companyRef back to companies/
    if echo "$meta_file" | grep -q "^components/"; then
        if ! grep -q "companyRef:" "$meta_file"; then
            echo "  ❌ missing required field: companyRef (must point to companies/<slug>)"
            FOUND_ERRORS=1
        fi
    fi
done

if [ "$FOUND_ERRORS" -eq 1 ]; then
    echo "❌ Validation FAILED. Please resolve missing attributes."
    exit 1
else
    echo "✅ Validation PASSED. Ready for PR."
    exit 0
fi
