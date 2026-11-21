---
name: validate-helm-service
description: Use when the user wants to run the full automated validation suite against a Helm service definition — runs tools/service-validator, reports each PASS/FAIL test with details, and directs to fix-helm-service for any failures.
---

# validate-helm-service

Run the full automated validation suite against a service and report the results.
This skill is read-only — it validates and reports. Fixes are the domain of `fix-helm-service`.

## Step 1 — Resolve the service name

If the user hasn't specified which service, list available ones and ask:
```bash
ls services/
```

The service directory name is `<name>helm` (e.g. `openldaphelm`). Confirm the version
directory exists: `services/<name>helm/v1/`.

## Step 2 — Run the validator

Use `execute_command` to run:

```bash
python3 tools/service-validator --version v1 services/<name>helm
```

Capture the full output. The validator exits 0 if all tests pass, 1 if any fail.

## Step 3 — Parse and report results

Read every `[PASS]` / `[FAIL]` line from the output. Present a structured report:

```
Service: <name>helm  version: v1
─────────────────────────────────────────────
 #   Test name                   Result
─────────────────────────────────────────────
 0   directory-structure         PASS
 1   catalog-yaml                PASS
 2   schema-json                 PASS
 3   chart-yaml                  PASS
 4   values-yaml                 PASS
 5   tmpl-jinja                  PASS
 6   values-test-exists          PASS
 7   helm-template               PASS
 8   helm-template-images        PASS
 9   scc-keys                    PASS
10   byop-registry               PASS
11   service-name                PASS
12   yaml-safe                   PASS
13   no-byop-registry-in-test    PASS
─────────────────────────────────────────────
Result: 14/14 PASS  ✓  Production ready
```

For each `[FAIL]` line, include the error detail from the validator output on the next line.

## Step 4 — On failures: enumerate and direct

If any tests failed, output a numbered list:

```
FAILURES FOUND — action required:

  [Test 7] helm-template
    Error: <exact error line from validator output>
    Fix:   See fix-helm-service Check 12 — Helm chart must render without errors

  [Test 9] scc-keys
    Error: <exact error line from validator output>
    Fix:   See fix-helm-service Check 4 — add fsGroup: null and seccompProfile to chart/values.yaml
```

Then recommend: **Load `fix-helm-service` to resolve these failures.**

Test-to-check mapping for directing the engineer to the right fix:

| Test # | Failing test name | fix-helm-service Check |
|--------|-------------------|------------------------|
| 0 | directory-structure | Check 1 (missing files) |
| 1 | catalog-yaml | Check 1 |
| 2 | schema-json | Check 2 |
| 3 | chart-yaml | Check 5 (Chart.yaml) |
| 4 | values-yaml | Check 5 (chart/values.yaml) |
| 5 | tmpl-jinja | Check 3 (template syntax) |
| 6 | values-test-exists | Check 9 |
| 7 | helm-template | Check 12 |
| 8 | helm-template-images | Check 5 + Check 8 (image ref completeness) |
| 9 | scc-keys | Check 4 |
| 10 | byop-registry | Check 5 (BYOP_REGISTRY in tmpl) |
| 11 | service-name | Not fixable post-creation — directory must be renamed |
| 12 | yaml-safe | Check 2 (yaml_safe on x-generate fields) |
| 13 | no-byop-registry-in-test | Check 9 (values-test.yaml registry) |

## Step 5 — On full pass: confirm production-ready

If all 14 tests pass, confirm:

```
✓ <name>helm v1 — all 14 validator tests pass.

The service definition is production-ready:
  • Platform wrapper files are complete and consistent
  • Helm chart renders without errors
  • Image references are complete (registry/repository:tag)
  • SCC defaults are OpenShift restricted-v2 compatible
  • BYOP_REGISTRY placeholder is correctly used in the template
  • values-test.yaml is clean (no BYOP_REGISTRY, usable without an air-gap registry)
```
