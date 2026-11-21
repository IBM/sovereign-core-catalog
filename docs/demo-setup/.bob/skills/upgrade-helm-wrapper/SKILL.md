---
name: upgrade-helm-wrapper
description: Use when the user wants to upgrade the vendored upstream subchart inside an existing umbrella wrapper chart service (e.g. services/redishelm/v2, services/valkeyhelm/v2) — discovers upstream versions, pulls the untarred chart, replaces chart/charts/<name>/, bumps the wrapper Chart.yaml, diffs upstream values.yaml for removed or renamed keys, then verifies with helm, service-render-check and service-validator.
---

# upgrade-helm-wrapper

Upgrade the upstream chart vendored in `services/<name>helm/<ver>/chart/charts/<subchart>/`.
This applies only to **umbrella wrapper charts** (a wrapper `chart/Chart.yaml` with a `file://./charts/<subchart>`
dependency). For a hand-patched monolithic chart, load `migrate-helm-wrapper` first.

**Golden rule:** the only files that normally change are `chart/charts/<subchart>/` and the wrapper
`chart/Chart.yaml`. If the key diff in Step 4 shows a mapped key was removed or renamed, update
`template/values.yaml.tmpl`, `values-test.yaml` and `chart/values.yaml` too. **Never edit a file inside
`chart/charts/<subchart>/`** — it must stay byte-identical to the upstream release.

Paths are relative to the `byop-sample-repo` root. Python tools need PyYAML and Jinja2; use the venv
(`python3 -m venv /tmp/jv && /tmp/jv/bin/pip install jinja2 pyyaml`) and call `/tmp/jv/bin/python`.

## Step 1 — Identify the service and current state

If the user hasn't named a service, list wrapper services:
```bash
grep -l "file://./charts/" services/*/v*/chart/Chart.yaml
```

Set `SVC=services/<name>helm/<ver>` and read:
- `$SVC/chart/Chart.yaml` — wrapper `appVersion` and the dependency `name` / `version` (current)
- `$SVC/chart/charts/<subchart>/Chart.yaml` — must match the dependency version
- `$SVC/template/values.yaml.tmpl` — pinned `image.tag`
- `$SVC/README.md` — records the upstream project (repo URL)

Confirm the baseline is green **before** changing anything, so failures can be attributed to the bump:
```bash
/tmp/jv/bin/python tools/service-render-check <name>helm/<ver>
PATH=/tmp/jv/bin:$PATH bash tools/service-validator --version <ver> <name>helm
```
If the baseline fails, stop and use `fix-helm-service`.

Record the rendered resource kinds/names so Step 8 can prove they did not change (names must be stable on live clusters):
```bash
helm template t $SVC/chart | grep -E "^kind:|^  name:" > /tmp/before.txt
```

## Step 2 — Discover upstream versions

For Groundhog2k charts (redis, valkey, mysql, postgres, mongodb, rabbitmq, etcd, memcached):
```bash
helm repo add groundhog2k https://groundhog2k.github.io/helm-charts/ 2>/dev/null
helm repo update groundhog2k
helm search repo groundhog2k/<subchart> --versions | head -10
```
For any other upstream, use the repository URL from the service README or the vendored
`Chart.yaml` (`home`, `sources`, `maintainers[].url`). If it can't be determined, ask the user with
`ask_followup_question`.

Pick the target version (default: latest stable; never a pre-release unless the user asks).
Check the upstream release notes / changelog for breaking changes before pulling.

## Step 3 — Pull the new chart untarred (do not touch the service yet)

```bash
rm -rf /tmp/up && mkdir /tmp/up
helm pull <repo>/<subchart> --version <new-version> --untar --untardir /tmp/up
ls /tmp/up/<subchart>/Chart.yaml
```

Always **untar** — the project stores subcharts as unpacked directories (traceable in git, renders offline
in ArgoCD without `.tgz` or `Chart.lock`).

## Step 4 — Dry-run key diff (flag removed / renamed keys)

```bash
/tmp/jv/bin/python .bob/skills/upgrade-helm-wrapper/diff_values.py $SVC /tmp/up/<subchart>
```

The script compares OLD `chart/charts/<subchart>/values.yaml` with the NEW upstream one and checks every key the
wrapper sets under `<subchart>:` (`chart/values.yaml`, `values-test.yaml`, `template/values.yaml.tmpl`).

| Output | Meaning | Action |
|---|---|---|
| `[BREAKING] <subchart>.<key>` (exit 1) | A mapped key exists in OLD and is gone in NEW | Find the replacement in the NEW `values.yaml` / upstream changelog; update **every** wrapper file listed in "set in …" before continuing. If there is no replacement, stop and report to the user. |
| `[WARN]` | Key is not in upstream OLD or NEW (e.g. `seccompProfile.type` which upstream leaves unset) | Usually benign — the wrapper adds it on purpose. Confirm in Step 6 that it renders. |
| `REMOVED/RENAMED upstream keys` not mapped by the wrapper | Upstream cleanup | Informational |
| `CHANGED upstream defaults` | Default changed (image tags, resources, probes, security contexts) | Read each one. A changed `securityContext` / `podSecurityContext` default may need a matching null/override in `chart/values.yaml` (Step 6). A changed exporter image tag needs a mirror entry if `metrics.enabled` is on. |
| `ADDED upstream keys` | New features | Informational |

Also glance at the template-level diff for structural changes (new/removed resources, selector labels):
```bash
diff -rq $SVC/chart/charts/<subchart>/templates /tmp/up/<subchart>/templates
```
> ⚠️ **StatefulSet selector immutability:** if `spec.selector.matchLabels` or `volumeClaimTemplates` changed in
> the NEW StatefulSet template, existing instances cannot be upgraded in place. Stop and tell the user
> a new service version (`v3`) is needed rather than bumping `v2`.

## Step 5 — Replace the vendored chart and bump the wrapper

```bash
rm -rf $SVC/chart/charts/<subchart>
cp -R /tmp/up/<subchart> $SVC/chart/charts/<subchart>
diff -r /tmp/up/<subchart> $SVC/chart/charts/<subchart> && echo "byte-identical"
```

Edit `$SVC/chart/Chart.yaml`:
- `dependencies[0].version` → the new chart version (must equal `chart/charts/<subchart>/Chart.yaml` `version`)
- `appVersion` → the new upstream `appVersion` (read it from the vendored `Chart.yaml`)
- Leave wrapper `name`, `version` and `repository: "file://./charts/<subchart>"` unchanged

## Step 6 — Decide on the image tag and update the dependent files

The upstream `appVersion` changing does **not** change what BYOP deploys: the tag is pinned in the template.
Ask the user whether to bump the application image too. If **no**, skip to Step 7 (the chart bump alone is valid,
as demonstrated by the Sub-Task 5 pilot). If **yes**, update all of:

| File | Change |
|---|---|
| `$SVC/template/values.yaml.tmpl` | `<subchart>.image.tag` |
| `$SVC/imagesetconfiguration.yaml` | `additionalImages` entry — upstream ref `docker.io/…:<tag>`; add the exporter image if `metrics.enabled` is true by default |
| `image-mapping.txt` | The `<upstream ref> -> localhost:5000/byop/<name>:<tag>` line under `# <name>helm` |
| `$SVC/chart/Chart.yaml` | `appVersion` (already done in Step 5; keep equal to the pinned tag if you pin a different one) |
| `$SVC/README.md` | Upstream chart version / image tag mentions |

Verify the new image exists before pinning:
```bash
skopeo inspect --no-tags docker://docker.io/library/<name>:<tag> >/dev/null && echo exists
```
(`values-test.yaml` uses its own upstream tag by design — change only if the old tag no longer exists.)

SCC check — the vendored chart's defaults may have changed. The wrapper `chart/values.yaml` must still null
out hard-coded UIDs/GIDs. Render with at least one user-supplied subchart value, exactly as the broker does:
```bash
helm template t $SVC/chart --set <subchart>.fullnameOverride=t | grep -nE "runAsUser|runAsGroup|fsGroup|supplementalGroups"
```
The output must be empty. Any numeric value means the new upstream added a hard-coded ID; add the matching `null`
to `$SVC/chart/values.yaml` under `<subchart>:`.

> ⚠️ **Always pass a value when checking SCC.** A bare `helm template t $SVC/chart` (no `-f`/`--set`) does **not**
> apply the wrapper's `null` deletions to the subchart defaults and shows upstream `999` IDs even on a healthy
> wrapper (observed with Helm v4.3.0 on the unmodified v2 baseline). It is not a real defect: the broker always
> supplies a values file. Likewise `values-test.yaml` sets UID/GID 1000 on purpose for non-OpenShift clusters, so
> it is not a valid SCC check either.

## Step 7 — Offline dependency validation (in a scratch copy)

Prove the `file://` dependency resolves without network access and the chart packages cleanly.
`helm dependency build` writes `Chart.lock` and a `charts/<subchart>-<ver>.tgz` that must **not** land in the repo,
so run it on a copy:
```bash
rm -rf /tmp/dbt && mkdir /tmp/dbt && cp -R $SVC/chart /tmp/dbt/chart
helm dependency build /tmp/dbt/chart
helm lint /tmp/dbt/chart
rm -rf /tmp/dbt
```
Then confirm the service tree is clean of artifacts:
```bash
find $SVC/chart -maxdepth 2 \( -name Chart.lock -o -name '*.tgz' \)   # must print nothing
```
If anything is listed, delete it — the project convention is unpacked directories only.

## Step 8 — Render and validate

```bash
helm template <name>-test $SVC/chart -f $SVC/values-test.yaml | head -80     # must exit 0
/tmp/jv/bin/python tools/service-render-check <name>helm/<ver>              # production template + helm template
PATH=/tmp/jv/bin:$PATH bash tools/service-validator --version <ver> <name>helm
```
`service-render-check` renders the real `values.yaml.tmpl` with the broker's own renderer and asserts labels,
annotations, `imagePullSecrets`, `BYOP_REGISTRY/` image prefix and PVC size — all must be `[PASS]`
(`N passed, 0 failed`). `service-validator` must report `ALL TESTS PASSED`.

> `service-validator` is a **bash** script (`bash tools/service-validator`, not `python3`); it shells out to
> `python3` for YAML checks, so put `/tmp/jv/bin` first on `PATH`.

Additionally confirm the rendered resource kinds/names are unchanged from the Step 1 baseline:
```bash
helm template t $SVC/chart | grep -E "^kind:|^  name:" > /tmp/after.txt
diff /tmp/before.txt /tmp/after.txt && echo "resource names unchanged"
```

### On failure

| Symptom | Likely cause | Fix |
|---|---|---|
| `helm template` error: `nil pointer` / `wrong type` | Mapped key changed type upstream | Re-check Step 4; adjust the wrapper mapping |
| `service-render-check`: labels/annotations missing | Upstream renamed `customLabels` / `podLabels` etc. | Update `template/values.yaml.tmpl` and `values-test.yaml` to the new key names |
| `service-render-check`: images don't start with `BYOP_REGISTRY/` | Upstream changed the image block structure (e.g. `registry` removed) | Update `<subchart>.image.*` mapping in the template |
| Resource names changed | `fullnameOverride` no longer honoured or helper renamed | Do not ship; report to the user — a new service version is required |
| Any wrapper-mapped change cannot be absorbed | Breaking upstream change | Revert (below) and record the schema diff as a follow-up |

### Revert

```bash
git checkout -- $SVC && git clean -fd $SVC
```

## Step 9 — Report

Summarise to the user:
- Upgrade performed: `<subchart> <old> → <new>` (appVersion `<old>` → `<new>`)
- Files changed outside `chart/charts/<subchart>/` and `chart/Chart.yaml` (ideally none), and why
- Key diff result (breaking / warn counts) and changed defaults of note
- `service-render-check` N/N passed; `service-validator` N/N passed
- Whether the application image tag was also bumped
- Anything not verified (live ArgoCD sync, running pod behaviour) — only a cluster test can confirm it; offer `test-helm-service`

Do not commit unless the user asks.
