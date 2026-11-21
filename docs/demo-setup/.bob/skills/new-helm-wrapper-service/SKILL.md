---
name: new-helm-wrapper-service
description: Use when the user wants to create a NEW Helm-based service definition from an upstream chart as an umbrella wrapper chart (the default for all new Helm services) — gathers chart repo/name/version and parameters, runs scaffold.py to vendor the unmodified upstream chart into chart/charts/<subchart>/ and generate the wrapper Chart.yaml/values.yaml (OpenShift SCC), template, schema, catalog, ApplicationSet, imagesetconfiguration, values-test.yaml and README, then validates with service-render-check and service-validator. Supersedes new-helm-service for charts that have an upstream.
---

# new-helm-wrapper-service

Create `services/<name>helm/v1/` as an **umbrella wrapper chart**: the upstream chart is pulled and vendored
**unmodified** in `chart/charts/<subchart>/`, and everything the platform needs is expressed as values under the
`<subchart>:` key. Reference implementations:
`services/redishelm/v2/`, `services/valkeyhelm/v2/`.

Use this skill instead of `new-helm-service` whenever an upstream chart exists. It removes the manual steps of that
skill: no image-split edits to templates, no `fsGroup: null` edits in upstream files, no template surgery.
If there is no upstream chart (you must author one), use `new-helm-service`. To convert an existing v1 service use
`migrate-helm-wrapper`.

Rules that never change:
- **Never edit anything under `chart/charts/<subchart>/`.** If a platform behaviour cannot be reached through values,
  report it to the user instead of patching the chart.
- Service name: lowercase `[a-z]+`, ≤ 22 chars (the broker appends `helm-<uuid>`). `helm` is appended for you.
- Only `{{ }}` / `{% %}` Jinja2 in `template/values.yaml.tmpl`; `| yaml_safe` on every `x-generate` field.
- `values-test.yaml` never contains `BYOP_REGISTRY`.

Run everything from the `byop-sample-repo` root. Tools need PyYAML + Jinja2 and `helm`:
`python3 -m venv /tmp/jv && /tmp/jv/bin/pip install jinja2 pyyaml`. `service-render-check` imports the broker's renderer —
set `BYOP_BROKER_SRC=<path>/byop-broker/broker/src` if `byop-broker` is not a sibling checkout.

## Step 1 — Gather requirements

Use `ask_followup_question` to collect:
- **Service name** (`[a-z]+`, ≤ 22) and a **display name** (e.g. "RabbitMQ Messaging")
- **Upstream chart**: repository URL + chart name (or an `oci://` reference) + version (default: latest stable)
- **Which credentials/parameters to expose** (password? username? database name? cookie?) — and for each, the
  **values path** in the chart where it goes (see Step 2)
- **Application image tag** to pin (default: the chart's `appVersion`)
- Is a sidecar exporter needed? (default: no — see Step 6)

Check it is not already there: `ls services | grep <name>helm`. Check the chart exists:
```bash
helm repo add <alias> <repo-url> 2>/dev/null; helm repo update <alias>
helm search repo <alias>/<chart> --versions | head -5
```
Preferred sources: Groundhog2k (`https://groundhog2k.github.io/helm-charts/`), or the official vendor chart. Confirm the
image comes from an acceptable registry (project convention is to mirror the upstream image to the `byop` org).

## Step 2 — Find where each credential goes

Pull the chart to a scratch dir and read its `values.yaml` — those keys are ground truth:
```bash
rm -rf /tmp/up && mkdir /tmp/up && helm pull <alias>/<chart> --version <v> --untar --untardir /tmp/up
grep -n -i "password\|user\|secret\|cookie\|database" /tmp/up/<chart>/values.yaml | head -30
```
Express each as `--secret NAME=values.path` (value goes to the path) or `--secret NAME=values.path:prefix`
(config-line style, written as a block scalar `values.path: |` / `prefix <value>`):

| Chart style | Flag | Rendered |
|---|---|---|
| nested `authentication.password.value` (rabbitmq, mysql `settings.rootPassword.value`) | `--secret password=authentication.password.value` | `value: {{ spec.password \| yaml_safe }}` |
| config text (redis `redisConfig`, valkey `valkeyConfig`) | `--secret password=valkeyConfig:requirepass` | `valkeyConfig: \|` newline `requirepass {{ spec.password \| yaml_safe }}` |

Each `--secret` creates a catalog parameter with `x-generate` (auto-generated 32-char password, charset includes `{}`,
hence `yaml_safe`). Non-secret parameters (database name, replicas…) are added by hand in Step 5.

## Step 3 — Run the scaffolder

```bash
/tmp/jv/bin/python .bob/skills/new-helm-wrapper-service/scaffold.py \
    --name     rabbitmq \
    --display  "RabbitMQ Messaging" \
    --chart    rabbitmq \
    --repo     https://groundhog2k.github.io/helm-charts/ \
    --chart-version 2.3.9 \
    --secret username=authentication.user.value \
    --secret password=authentication.password.value \
    --secret erlang_cookie=authentication.erlangCookie.value
```
(`--image-tag` overrides the pinned tag; `--version v2` for a non-v1 directory; `--description` for the catalog.)

What it does, in order — read its output:
1. `helm pull --untar` of the chart into a temp dir.
2. **Inspects what the vendored templates actually read**: workload labels/annotations (`customLabels`/`commonLabels`…),
   pod labels/annotations (`podLabels`/`podAnnotations`), `imagePullSecrets`, `fullnameOverride`, `storage.requestedSize`.
   The 69 % silent-failure defect came from sending keys the chart ignores — the scaffolder only emits keys it found.
3. Finds **every image block** in `values.yaml` (`repository` + `tag`) and keeps those that render by default (e.g. the
   rabbitmq `initImage` busybox is kept; a disabled metrics exporter is not). Warns about images hard-coded in the chart.
4. Nulls the numeric UID/GID keys the upstream sets in `podSecurityContext`/`securityContext` (OpenShift `restricted-v2`) and
   adds `seccompProfile: RuntimeDefault`.
5. Writes the service and **copies the chart byte-identical** to `chart/charts/<subchart>/`.
6. Runs `helm template` with the generated `values-test.yaml` and warns about a StatefulSet without a headless service.

It refuses to overwrite an existing service, validates the name, and exits **2** with nothing written on any error.
Exit **1** means it scaffolded but printed `[WARN]` lines you must resolve (Step 7). Exit **0** is clean.

**Files created:**

| File | Content |
|---|---|
| `chart/Chart.yaml` | `<subchart>-byop` wrapper, `file://./charts/<subchart>` dependency |
| `chart/values.yaml` | OpenShift SCC defaults under `<subchart>:` |
| `chart/charts/<subchart>/` | Unmodified upstream chart |
| `template/values.yaml.tmpl` | `fullnameOverride`, labels, annotations, pod labels/annotations, `imagePullSecrets`, `BYOP_REGISTRY` images, secrets, `storage.requestedSize` — all under `<subchart>:` |
| `values-test.yaml` | Same keys resolved to local values, upstream registry, SCC relaxed to UID 1000 |
| `catalog/{catalog.yaml,schema.json,metrics.json}` | From the shared `new-helm-service` templates + generated parameters |
| `argocd/applicationset-helm.yaml.tmpl` | Verbatim shared template |
| `imagesetconfiguration.yaml` | One mirror entry per rendered image |
| `README.md` | Wrapper layout, parameters, key values, upgrade pointer |

## Step 4 — Add the `image-mapping.txt` entries

The scaffolder prints the lines. Add them to the repo-root `image-mapping.txt` under a `# <name>helm` comment:
```
# <name>helm
docker.io/library/rabbitmq:4.3.6  ->  localhost:5000/byop/rabbitmq:4.3.6
docker.io/library/busybox:stable  ->  localhost:5000/byop/busybox:stable
```
Skip an entry that already exists (e.g. busybox is shared). `BYOP_REGISTRY -> …` at the top resolves the placeholder.

## Step 5 — Review and complete the generated files

Open and sanity-check each file; the scaffolder is deterministic but cannot know your intent:
- `catalog/schema.json` — improve parameter `description`s; add non-secret parameters (pattern/min/max/default), then map each in
  `template/values.yaml.tmpl` as `spec.<name>` and in `values-test.yaml`. Every schema property must be used in the template
  (validator test 4).
- `catalog/catalog.yaml` — fix the plan descriptions if generic.
- `template/values.yaml.tmpl` — confirm secondary `image` blocks, optional `storage.className`, any chart-specific required
  values (e.g. rabbitmq `erlangCookie` is mandatory). Never put `podSecurityContext`/`securityContext` here.
- `imagesetconfiguration.yaml` — upstream refs (`docker.io/library/<image>:<tag>`, with the `library/` prefix for Docker Hub
  official images).

## Step 6 — Optional: metrics exporter

By default the scaffolder skips images that do not render with default values (a disabled exporter). To enable metrics:
set `<subchart>.metrics.enabled: true` (and the exporter image block) in `template/values.yaml.tmpl` **and**
`values-test.yaml`, add the exporter image to `imagesetconfiguration.yaml` and `image-mapping.txt`, and re-run Step 8.
Check whether the chart renders a `ServiceMonitor` itself before adding one; fill `catalog/metrics.json` per the other services.

## Step 7 — Resolve warnings

| `[WARN]` | Meaning | Action |
|---|---|---|
| upstream chart reads none of `[customLabels…]` / `[podLabels]` … | The chart has no values knob for that metadata | Do **not** patch the chart. Tell the user which resources cannot carry platform labels/annotations. Check the chart's own docs for another knob (`global.*`, `extraLabels`) and set it by hand in the template and `values-test.yaml` |
| upstream does not read `imagePullSecrets` / `fullnameOverride` | No pull-secret or deterministic-name support | Look for the chart's equivalent (`global.imagePullSecrets`); otherwise report to the user |
| no `storage.requestedSize` | Different PVC key (`persistence.size`, `volumeClaimTemplates`) | Map `{{ storage_size }}` to it by hand in template + values-test (`service-render-check` then verifies the PVC size) |
| upstream has no `podSecurityContext`/`securityContext` | Security context lives elsewhere (e.g. `containerSecurityContext`) | Find the real keys; null any numeric UID/GID in `chart/values.yaml`, add `seccompProfile` |
| rendered image is hard-coded in the chart | Cannot be redirected to `BYOP_REGISTRY` through values | Report to the user — the air-gap cannot be satisfied without patching |
| StatefulSet without `clusterIP: None` Service | Upstream has no headless service | Groundhog2k mysql also has none (its `serviceName` points at a normal Service). Do not copy a duplicate; tell the user. Only add `chart/templates/service-headless.yaml` (named `{{ .Values.<subchart>.fullnameOverride }}-headless`, `clusterIP: None`, `publishNotReadyAddresses: true`) if the StatefulSet `serviceName` truly needs it, and note it in the README |
| `helm template … FAILED` | Chart needs a value that was not mapped | Add the required value to template **and** `values-test.yaml` |

## Step 8 — Validate

```bash
export BYOP_BROKER_SRC=<path>/byop-broker/broker/src
/tmp/jv/bin/python tools/service-render-check <name>helm/v1                      # production template → broker renderer → helm template
PATH=/tmp/jv/bin:$PATH bash tools/service-validator --version v1 <name>helm      # 6 static tests (bash script, needs PyYAML on PATH)
helm template <name>-test services/<name>helm/v1/chart -f services/<name>helm/v1/values-test.yaml | grep "image:"
helm template t services/<name>helm/v1/chart --set <subchart>.fullnameOverride=t | grep -nE "fsGroup:|runAsUser|runAsGroup|supplementalGroups"   # must be empty
find services/<name>helm/v1/chart -maxdepth 2 \( -name Chart.lock -o -name '*.tgz' \)                                                    # must be empty
```
Expected: `N passed, 0 failed`; `ALL TESTS PASSED (6/6)`; complete `registry/repository:tag` image lines; two empty outputs.

Notes: pass a value in the SCC check — a bare `helm template` (no `-f`/`--set`) shows the upstream's 999 even on a healthy
wrapper. `fsGroupChangePolicy` (rabbitmq) is a non-numeric policy and is fine. Do not run `helm dependency build` in the
service tree (it writes `Chart.lock` and a `.tgz`); to prove offline resolution, run it on a copy in `/tmp`.

## Step 9 — Report

Tell the user: service created, chart + version vendored, files generated, every `[WARN]` and how it was resolved,
parameters exposed, images mirrored, validation results (`service-render-check N/N`, `service-validator 6/6`), and what was
**not** verified (live ArgoCD sync, running pods — offer `test-helm-service`). Remind them that upgrading the upstream chart later is the
`upgrade-helm-wrapper` skill. Do not commit unless asked.
