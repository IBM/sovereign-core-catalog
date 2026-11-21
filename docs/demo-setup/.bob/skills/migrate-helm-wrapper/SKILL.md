---
name: migrate-helm-wrapper
description: Use when the user wants to migrate an existing hand-patched Helm service (services/<name>helm/v1) to an umbrella wrapper chart as a new v2 — audits v1 against the pristine upstream chart, vendors the unmodified upstream into v2/chart/charts/<subchart>/, writes the wrapper Chart.yaml/values.yaml (OpenShift SCC), moves template/values.yaml.tmpl and values-test.yaml into the <subchart>.* namespace, and proves v2 renders the same resources as v1 with service-render-check and service-validator.
---

# migrate-helm-wrapper

Convert a monolithic, hand-patched `services/<name>helm/v1/` into an **umbrella wrapper chart** at
`services/<name>helm/v2/`.
Pilots: `redishelm/v2`, `valkeyhelm/v2` (Groundhog2k). Proven again on `mysqldbhelm`.

Rules that never change:
- **`v1` is never modified.** v2 is a copy; v1 is the rollback path and keeps serving existing instances.
- **`chart/charts/<subchart>/` is byte-identical to the upstream release.** No edits, ever. All platform
  behaviour is expressed as values under `<subchart>:` and, only if truly needed, wrapper `chart/templates/`.
- Resource **names and StatefulSet selectors must not change** between v1 and v2 (selectors are immutable).

Paths are relative to the `byop-sample-repo` root. Python tools need PyYAML and Jinja2 — use the venv
(`python3 -m venv /tmp/jv && /tmp/jv/bin/pip install jinja2 pyyaml`). `service-render-check` imports the broker's
renderer: set `BYOP_BROKER_SRC=<path>/byop-broker/broker/src` if `byop-broker` is not a sibling checkout.

## Step 1 — Pick the service and check it is eligible

If the user hasn't named one, list candidates (v1 only, Helm):
```bash
for s in services/*helm; do [ -d $s/v2 ] || echo "$s: $(ls $s | tr '\n' ' ')"; done
```

Read `services/<name>helm/v1/chart/Chart.yaml` and the service README, then decide:

| Finding | Eligible? |
|---|---|
| Chart from a public upstream (`maintainers`/`home`/`sources` point to a project; `helm search repo` finds it) | **Yes** — continue |
| BYOP/in-house chart (maintainer `byop`, no upstream; e.g. `memcachedhelm`, `openldaphelm`, `mariadbhelm`) | **No.** There is nothing to vendor. Tell the user; keep it as is, or if a real upstream exists, treat it as a new service with `new-helm-wrapper-service` |
| Kustomize (`mariadbkz`) | **No** |
| Already has a `v2` | **No** — use `upgrade-helm-wrapper` |

Common upstream origins and the label/annotation/registry knobs they read. **These are starting points, not facts
— always confirm with the grep in Step 3**, because the whole point of this migration is that platform keys were
silently ignored by 11 of 16 charts.

| Origin | Services | Workload labels / annotations | Pod labels / annotations | Names | Pull secrets / registry |
|---|---|---|---|---|---|
| **Groundhog2k** (`groundhog2k/<name>`, repo `https://groundhog2k.github.io/helm-charts/`) | etcd, mongodb, mysql, postgres, rabbitmq, redis, valkey | `customLabels` / `customAnnotations` | `podLabels` / `podAnnotations` | `fullnameOverride` | `imagePullSecrets`, `image.registry`; PVC `storage.requestedSize` |
| **Bitnami** | (none yet) | `commonLabels` / `commonAnnotations` | `podLabels` / `podAnnotations` | `fullnameOverride` | `global.imagePullSecrets`, `global.imageRegistry` or per-image `image.registry`; size under e.g. `primary.persistence.size`. Verify image availability and the project's image-source policy before choosing |
| **Official / vendor** | vault (HashiCorp), ollama (otwld), keycloak (kubelauncher), odoo (IMIO), langflow | Varies. Vault uses `global.*`; ollama has no `commonLabels` (pod-level `podLabels`/`podAnnotations` only) | see left | `fullnameOverride` usually | Varies — read the chart's `values.yaml` |

Charts with their own sub-dependencies (keycloak → postgres, odoo → postgres, langflow → postgresql) have **nested**
subcharts: the vendored chart keeps its own `charts/` untouched, and you map values for both levels. Treat these as
a larger job; confirm scope with the user first.

## Step 2 — Audit v1 against the pristine upstream

Pull the **same chart version v1 is based on** (so any difference is a hand-patch, not an upgrade):
```bash
SVC=services/<name>helm
helm repo add groundhog2k https://groundhog2k.github.io/helm-charts/ 2>/dev/null; helm repo update groundhog2k
rm -rf /tmp/mig && mkdir /tmp/mig
helm pull groundhog2k/<subchart> --version <v1 chart version> --untar --untardir /tmp/mig
diff -r /tmp/mig/<subchart> $SVC/v1/chart
```
(`--version` = `version:` in v1's `Chart.yaml`. For other origins add their repo first.) If that exact version is
no longer published, pull the nearest one and note it.

Classify **every** difference; this is the migration to-do list:

| v1 difference | Becomes in v2 |
|---|---|
| `fsGroup`/`runAsUser`/`runAsGroup`/`supplementalGroups` nulled, `seccompProfile` added | wrapper `chart/values.yaml` under `<subchart>:` (Step 4) |
| `appVersion` changed in `Chart.yaml` | `image.tag` pinned in `template/values.yaml.tmpl`; wrapper `appVersion` (Step 4) |
| Comment / whitespace / icon edits | Drop — not behaviour |
| Template logic edit (e.g. `replicas: {{ .Values.replicas \| default 1 }}` in place of `replicas: 1`) | **Decision needed.** If `replicas` is not a catalog parameter, drop it (upstream default applies). If it is, see if the chart has a native knob (`haMode`, `replicaCount`); otherwise tell the user it cannot be done without patching upstream |
| Extra templates present in v1 but not upstream (e.g. `service-headless.yaml`, `servicemonitor.yaml`, `networkpolicy.yaml`) | Wrapper `chart/templates/` **only if the upstream subchart does not already render an equivalent** (Step 6) |

Also record the baseline resources of v1 for the later comparison (Step 9):
```bash
helm template <name>helm-test $SVC/v1/chart -f $SVC/v1/values-test.yaml | grep -E "^kind:|^  name:" > /tmp/v1.txt
```
> If v1's `values-test.yaml` does not render, that is a pre-existing bug (e.g. `postgreshelm/v1` is an unedited copy of
> `mysqldbhelm`). Note it, and build the v1 baseline from a minimal values file instead.

## Step 3 — Create v2 and vendor the pristine chart

```bash
cp -R $SVC/v1 $SVC/v2
rm -rf $SVC/v2/chart && mkdir -p $SVC/v2/chart/charts
cp -R /tmp/mig/<subchart> $SVC/v2/chart/charts/<subchart>
cp services/redishelm/v2/chart/.helmignore $SVC/v2/chart/.helmignore
diff -r /tmp/mig/<subchart> $SVC/v2/chart/charts/<subchart> && echo byte-identical
```
Do **not** use `Chart.lock` or `.tgz` archives — unpacked directories only (offline ArgoCD, git-traceable).

Confirm which platform knobs the **vendored** chart actually reads. Every key you intend to send must appear here:
```bash
grep -rn "Values.customLabels\|Values.customAnnotations\|Values.podLabels\|Values.podAnnotations\|Values.imagePullSecrets\|Values.fullnameOverride\|Values.namespaceOverride" $SVC/v2/chart/charts/<subchart>/templates | head -20
```
Use the actual knob names you find. If the chart reads no label/annotation knob for a resource, that resource cannot
carry platform metadata through values; report it to the user (do not patch upstream).

## Step 4 — Write the wrapper `Chart.yaml` and `values.yaml`

`$SVC/v2/chart/Chart.yaml`:
```yaml
apiVersion: v2
name: <subchart>-byop
description: BYOP platform wrapper around the unmodified <origin> <Product> chart
type: application
version: "1.0.0"
appVersion: "<pinned image tag, e.g. 9.7.1>"
dependencies:
  - name: <subchart>
    version: "<vendored chart version>"
    repository: "file://./charts/<subchart>"
```
`$SVC/v2/chart/values.yaml` (OpenShift `restricted-v2`; `null` deletes the upstream hard-coded key):
```yaml
# BYOP wrapper defaults for <name>helm.
# The upstream <origin>/<subchart> chart is vendored unchanged in charts/<subchart>/.
# Everything here is passed to it through the `<subchart>:` subchart namespace.

<subchart>:
  podSecurityContext:
    fsGroup: null
    supplementalGroups: null
    seccompProfile:
      type: RuntimeDefault

  securityContext:
    runAsUser: null
    runAsGroup: null
    seccompProfile:
      type: RuntimeDefault
```
Adjust to what the vendored `values.yaml` actually defines (`grep -n "SecurityContext" -A8 …/values.yaml`): null every
numeric UID/GID, add `seccompProfile`. Keep upstream's `runAsNonRoot`, `readOnlyRootFilesystem`, `capabilities.drop`
(they stay inherited). Service-validator test 9 (`runAsNonRoot`, `fsGroup: null`, `seccompProfile`) is satisfied by the
combination.

## Step 5 — Transform `template/values.yaml.tmpl`

Rewrite `$SVC/v2/template/values.yaml.tmpl` so that **everything is nested under `<subchart>:`** (indent v1's
chart-specific blocks by two spaces) and the platform header becomes:

```yaml
# Helm values override for instance
# All keys live under `<subchart>:` — the vendored <origin> subchart in chart/charts/<subchart>/.
<subchart>:
  fullnameOverride: {{ service_type }}-{{ instance_name }}

  customLabels:
    app: <service-name>
    service-type: <service-name>

  customAnnotations:
    sovcore.byop.ibm.com/crn: {{ context.crn | default("crn:unknown") | yaml_safe }}
    sovcore.byop.ibm.com/account-id: {{ context.account_id | default("unknown") | yaml_safe }}
    sovcore.byop.ibm.com/sub-account-id: {{ context.sub_account_id | default("unknown") | yaml_safe }}
    sovcore.byop.ibm.com/platform: {{ context.platform | default("unknown") | yaml_safe }}

  podLabels:
    app: <service-name>
    service-type: <service-name>

  podAnnotations:
    sovcore.byop.ibm.com/crn: {{ context.crn | default("crn:unknown") | yaml_safe }}
    sovcore.byop.ibm.com/account-id: {{ context.account_id | default("unknown") | yaml_safe }}
    sovcore.byop.ibm.com/sub-account-id: {{ context.sub_account_id | default("unknown") | yaml_safe }}
    sovcore.byop.ibm.com/platform: {{ context.platform | default("unknown") | yaml_safe }}

  imagePullSecrets:
{% if image_pull_secret_name %}
    - name: {{ image_pull_secret_name }}
{% else %}
    []
{% endif %}

  image:
    registry: BYOP_REGISTRY
    repository: byop/<image-name>
    tag: "<pinned-tag>"

  # …v1's chart-specific blocks (settings, userDatabase, storage, …), nested one level deeper
  storage:
    requestedSize: {{ storage_size }}
```
(Use the knob names found in Step 3 — the above is the Groundhog2k set.)

- **Drop** `namespaceOverride`, `commonLabels`, `commonAnnotations` and the `instance:` block. The upstream reads
  none of them (this was the 69 % silent-failure defect). ArgoCD guarantees the namespace.
- Keep `| yaml_safe` on **every** `x-generate` field. `imagePullSecrets` must be `- name: …`, never a bare string.
- Keep the `{% if %}…{% endif %}` lines at column 0 (Jinja block tags), nested YAML lines indented.
- Secondary images (exporter, init container) stay in the template, nested: `<subchart>.metrics.exporter.image.*`.
- No `podSecurityContext`/`securityContext` in the template — they live in the wrapper `chart/values.yaml`.

## Step 6 — Companion templates: add only what is missing

Check whether the upstream already renders what the platform needs before adding anything:
```bash
helm template t $SVC/v2/chart --set <subchart>.fullnameOverride=t | grep -E "^kind:|^  name:|clusterIP: None"
```
- **Headless Service:** a StatefulSet's `serviceName` must point to a `clusterIP: None` Service. Groundhog2k charts render
  `<fullname>-headless` (redis/valkey) — then add nothing. If `serviceName` points to a normal Service (e.g. mysql renders
  `serviceName: <fullname>` backed by a ClusterIP Service), do **not** add a wrapper copy that would duplicate
  or rename resources; keep v1's behaviour and flag it to the user as a known v1 parity item.
- **ServiceMonitor:** only if `metrics.enabled` is on by default and the upstream does not render one.

If a companion is genuinely required, add it under `$SVC/v2/chart/templates/` using `{{ .Release.Name }}`-based names
consistent with `fullnameOverride`, and note it in the README. Otherwise leave `chart/templates/` absent.

## Step 7 — `values-test.yaml` and `README.md`

`$SVC/v2/values-test.yaml`: mirror the new template with all variables resolved (see `redishelm/v2/values-test.yaml`):
everything under `<subchart>:`, `fullnameOverride: <name>helm-test`, `customLabels`/`customAnnotations`/`podLabels`/
`podAnnotations` filled in, `imagePullSecrets: []`, **upstream** image registry (never `BYOP_REGISTRY`), SCC overridden to
UID/GID 1000 for local clusters, `storage.className: "local-path"`. Keep the comment explaining that the old top-level
`customLabels` keys were a false-positive test bug.

`$SVC/v2/README.md`: copy `services/redishelm/v2/README.md`'s structure — intro paragraph stating v2 is an umbrella wrapper
and v1 is untouched; directory tree (wrapper `Chart.yaml`, `values.yaml`, `charts/<subchart>/` marked UNMODIFIED); the
"Key Helm values" table with `<subchart>.`-prefixed paths; an "Upgrading the upstream chart" pointer to
`upgrade-helm-wrapper`; test command. Keep the parameter and ApplicationSet tables.

## Step 8 — Files that stay as they are

Verify, don't edit, unless a diff shows otherwise: `catalog/catalog.yaml`, `catalog/schema.json`, `catalog/metrics.json`,
`argocd/applicationset-helm.yaml.tmpl` (ArgoCD reads `chart/`; the wrapper is transparent), and
`imagesetconfiguration.yaml` / `image-mapping.txt` (image refs unchanged because the pinned tag did not change; if you
changed the tag or added an exporter image, update both).

## Step 9 — Validate and prove parity with v1

```bash
export BYOP_BROKER_SRC=<path>/byop-broker/broker/src
# 1. production template -> broker renderer -> helm template -> platform contract
/tmp/jv/bin/python tools/service-render-check <name>helm/v2
# 2. static validator (bash script, needs PyYAML on PATH)
PATH=/tmp/jv/bin:$PATH bash tools/service-validator --version v2 <name>helm
# 3. v2 chart renders with test values
helm template <name>helm-test $SVC/v2/chart -f $SVC/v2/values-test.yaml > /tmp/v2.out
# 4. parity with v1: identical kinds and names
grep -E "^kind:|^  name:" /tmp/v2.out > /tmp/v2.txt && diff /tmp/v1.txt /tmp/v2.txt && echo "IDENTICAL kinds+names"
# 5. selectors and serviceName unchanged (immutable on live StatefulSets)
for v in v1 v2; do helm template <name>helm-test $SVC/$v/chart -f $SVC/$v/values-test.yaml | grep -A3 "serviceName\|matchLabels"; done
# 6. SCC: must print nothing (always pass a value — a bare helm template shows upstream 999 even when healthy)
helm template t $SVC/v2/chart --set <subchart>.fullnameOverride=t | grep -nE "runAsUser|runAsGroup|fsGroup|supplementalGroups"
# 7. no lock files or archives in the tree
find $SVC/v2/chart -maxdepth 2 \( -name Chart.lock -o -name '*.tgz' \)
```
Expected: `N passed, 0 failed` (2 cases × checks), `ALL TESTS PASSED`, `IDENTICAL kinds+names`, same selectors,
empty output for 6 and 7. `service-render-check` asserts labels and `sovcore.byop.ibm.com/*` annotations on **both**
the workload and the pod template, `imagePullSecrets` shape, `BYOP_REGISTRY/` image prefix and PVC size.

| Failure | Cause | Fix |
|---|---|---|
| `render-check`: `'dict object' has no attribute …` | Old tool versions only supplied `spec.password` | Use the current `tools/service-render-check` (builds `spec` from `schema.json`) |
| `render-check`: labels/annotations missing | Wrong knob name for this chart | Re-run the Step 3 grep; fix the template **and** `values-test.yaml` |
| `render-check`: images not `BYOP_REGISTRY/…` | `image.*` not under `<subchart>:` or chart uses a different image block | Fix nesting / mapping |
| kinds/names differ from v1 | `fullnameOverride` not set or not honoured | Do not ship; investigate |
| selectors differ | Upstream label scheme differs from v1's pristine base (e.g. you pulled a different version) | Re-pull v1's exact version, then use `upgrade-helm-wrapper` as a separate step |
| `helm template` type error on a secret (`b64enc … map`) | Value nested/typed differently than upstream expects | Compare with the vendored `values.yaml` shape |

## Step 10 — Report

Tell the user, concisely:
- Service, origin, chart version vendored, and that v1 is untouched
- Audit result: which v1 hand-patches were converted to wrapper values, which were dropped and why (esp. any behaviour
  loss such as a patched `replicas`)
- Whether any companion template was added (or why not)
- Validation: render-check `N/N`, validator `N/N`, kinds/names and selectors identical to v1
- Not verified: live ArgoCD sync, running pod behaviour (offer `test-helm-service`)
- Follow-ups: pre-existing v1 issues found (broken `values-test.yaml`, headless-service gap, etc.)

To roll back: `rm -rf services/<name>helm/v2`. Do not commit unless the user asks.
