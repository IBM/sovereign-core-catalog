---
name: test-helm-service
description: Use when the user wants to run a local smoke-test of a Helm service using its values-test.yaml — Phase 1 (always, non-destructive): helm template + dry-run; Phase 2 (on explicit user confirmation only): live install + rollout wait + cleanup.
---

# test-helm-service

Smoke-test a Helm service locally using its `values-test.yaml`.
Two phases: **Phase 1 is always non-destructive** (no cluster state touched).
**Phase 2 requires explicit user confirmation** and always cleans up after itself.

## Step 1 — Prerequisites check

Verify `values-test.yaml` exists:
```bash
ls services/<name>helm/v1/values-test.yaml
```

If missing: stop immediately. Direct the engineer to `fix-helm-service` Check 9 to create it.
Do not attempt to synthesise a values file — an incorrect file produces misleading test results.

Verify `helm` is available:
```bash
helm version --short
```

## Phase 1 — Static render checks (always run, non-destructive)

### Test P1.1 — helm template exits 0

```bash
helm template <name>-test services/<name>helm/v1/chart \
  -f services/<name>helm/v1/values-test.yaml 2>&1
```

- Exit code 0 → PASS
- Any error output → FAIL — report the exact error

### Test P1.2 — Image references are complete

From the helm template output, extract all `image:` lines:
```bash
helm template <name>-test services/<name>helm/v1/chart \
  -f services/<name>helm/v1/values-test.yaml 2>/dev/null | grep "image:"
```

Each line must match `<registry>/<repository>:<tag>` with no empty segment:
- No leading `/` (missing registry)
- No `//` (empty path segment)
- No trailing `:` (missing tag)
- No `: ` followed only by whitespace

PASS if all image lines are complete. FAIL with each offending line listed.

### Test P1.3 — SCC sanity in rendered manifests

Parse the full `helm template` output:
```bash
helm template <name>-test services/<name>helm/v1/chart \
  -f services/<name>helm/v1/values-test.yaml 2>/dev/null | \
  grep -E "runAsNonRoot|privileged:"
```

- `runAsNonRoot: true` must be present in at least one container securityContext → PASS
- `privileged: true` must not appear anywhere → FAIL if found

### Test P1.4 — Dry-run against cluster (skip gracefully if no cluster)

Check cluster reachability first:
```bash
kubectl cluster-info 2>&1 | head -2
```

If reachable, run:
```bash
helm install --dry-run --generate-name services/<name>helm/v1/chart \
  -f services/<name>helm/v1/values-test.yaml 2>&1 | tail -5
```
- Exit 0 → PASS
- Error → FAIL — report the exact error

If cluster is not reachable: skip with note `"No cluster reachable — P1.4 skipped (not an error)"`.

### Phase 1 summary

Print a structured report:
```
Phase 1 — Static render checks
──────────────────────────────────────────
 P1.1  helm template exits 0          PASS
 P1.2  image references complete       PASS
 P1.3  SCC sanity (runAsNonRoot)      PASS
 P1.4  helm install --dry-run         PASS  (or SKIPPED)
──────────────────────────────────────────
Phase 1: 4/4 PASS
```

If any Phase 1 test fails: report failures and recommend `fix-helm-service` before proceeding.
Do **not** offer Phase 2 if Phase 1 has failures.

---

## Phase 2 — Live install (requires explicit user confirmation)

> ⚠️ **Phase 2 touches cluster state.** Only proceed after explicit user confirmation.
> Cleanup runs regardless of pass/fail — never leave test resources behind.

### Gate — ask before proceeding

Use `ask_followup_question`:

> "Phase 1 passed. Run a live install on the active cluster? This will create namespace
> `<name>-test`, install the chart, wait for rollout, then clean up.
> Active context: `<kubectl config current-context output>`"

Only proceed if the user answers yes. If no: report Phase 1 results as final, done.

### Test P2.1 — helm upgrade --install

```bash
helm upgrade --install <name>-test services/<name>helm/v1/chart \
  -f services/<name>helm/v1/values-test.yaml \
  --create-namespace \
  --namespace <name>-test \
  --timeout 120s \
  --wait 2>&1
```

- Exit 0 → PASS
- Error → FAIL — record error, proceed to cleanup regardless

### Test P2.2 — Rollout status

Only run if P2.1 passed:
```bash
kubectl rollout status statefulset/<name>-test \
  -n <name>-test --timeout=120s 2>&1
```

If the StatefulSet name differs from `<name>-test`, use:
```bash
kubectl get statefulset -n <name>-test -o name | head -1
```

- Rollout complete within timeout → PASS
- Timeout or error → FAIL — record, proceed to cleanup

### Cleanup — always runs (pass or fail)

```bash
helm uninstall <name>-test --namespace <name>-test 2>&1
kubectl delete namespace <name>-test --ignore-not-found 2>&1
```

Always run both commands. Report cleanup result. Never skip cleanup.

### Phase 2 summary

```
Phase 2 — Live install
──────────────────────────────────────────
 P2.1  helm upgrade --install          PASS
 P2.2  rollout status                  PASS
 cleanup  helm uninstall + ns delete   OK
──────────────────────────────────────────
Phase 2: 2/2 PASS
```

---

## Final report

Print consolidated results from both phases and a one-line verdict:

```
<name>helm smoke-test — PASS (Phase 1: 4/4, Phase 2: 2/2)
```

or if Phase 2 was skipped:

```
<name>helm smoke-test — PASS (Phase 1: 4/4, Phase 2: skipped by user)
```
