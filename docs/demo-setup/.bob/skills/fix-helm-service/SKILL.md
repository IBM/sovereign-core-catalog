---
name: fix-helm-service
description: Use when the user wants to audit or fix an existing Helm service definition in this repository — checks and corrects template header (commonLabels/commonAnnotations/instance block/imagePullSecrets format), SCC settings, image registry/repository split, BYOP_REGISTRY placeholder, imagesetconfiguration.yaml completeness, StatefulSet headless service, ServiceMonitor/exporter wiring, metrics.json format, schema/template alignment, values-test.yaml, and README accuracy.
---

# fix-helm-service

Audit and correct an existing Helm service definition under `services/<name>helm/v1/`.
Work through each check in order. Only make changes where a real problem is found.

## Step 1 — Identify the service

If the user hasn't specified which service, list the available ones:
```bash
ls services/
```

Read the following files before making any changes:
- `services/<name>helm/v1/chart/Chart.yaml` (appVersion = canonical image tag)
- `services/<name>helm/v1/chart/values.yaml` (source of truth for value keys, image defaults, SCC)
- `services/<name>helm/v1/chart/templates/statefulset.yaml` (image rendering, label keys, serviceName)
- `services/<name>helm/v1/template/values.yaml.tmpl`
- `services/<name>helm/v1/imagesetconfiguration.yaml`
- `services/<name>helm/v1/catalog/catalog.yaml`
- `services/<name>helm/v1/catalog/schema.json`
- `services/<name>helm/v1/values-test.yaml` (if present)

## Check 1 — catalog.yaml correctness

> **Never auto-fix this check.** The plan list is intentional and correct — do not remove or consolidate plans, even if IDs look inconsistent across services.

Verify only:
- `name` matches the service directory name (e.g. `redishelm` not `mariadbhelm`)
- `display_name` is meaningful (not copied from another service)
- `description` mentions the correct technology

## Check 2 — schema.json correctness and yaml_safe coverage

Verify:
- `title` and `description` mention the correct service
- Properties match what the `values.yaml.tmpl` actually uses via `spec.<property>`
- No MariaDB-specific fields (`database_name`, `character_set`, `collation`) present on non-DB services
- Credential params have `x-generate` blocks
- `required` only lists fields with no sensible default

**yaml_safe rule (mandatory):** Every field in `schema.json` that has an `x-generate` block **must** use
`| yaml_safe` in `template/values.yaml.tmpl`. The `alphanumeric-symbols` charset includes `{` and `}`
which Helm silently drops if not escaped. Missing `| yaml_safe` causes Helm to silently render an empty value.

Check for violations:
```bash
# Find all x-generate field names in schema.json
python3 -c "
import json, sys
s = json.load(open('services/<name>helm/v1/catalog/schema.json'))
for k,v in s.get('properties',{}).items():
    if 'x-generate' in v:
        print(k)
"
# Then verify each one has | yaml_safe in the template:
grep "yaml_safe" services/<name>helm/v1/template/values.yaml.tmpl
```

If any `x-generate` field is referenced in the template **without** `| yaml_safe`, add it.

## Check 3 — template header completeness and correctness

The `template/values.yaml.tmpl` must have the following standard header. Check and fix each item:

### 3a — Namespace
```yaml
namespaceOverride: {{ namespace }}
```
Exception: HashiCorp Vault chart uses `global.namespace: {{ namespace }}` instead — leave as-is.

### 3b — Labels
```yaml
commonLabels:
  app: <service-name>
  service-type: <service-name>
```
- **Always use `commonLabels`** for the standard BYOP platform labels (`app`, `service-type`).
- **Never use `customLabels`** for BYOP platform metadata. `customLabels` is a chart-internal key that
  some upstream charts expose for their own purposes — it is never the channel for platform identity.
- Exception: otwld/ollama-helm has no `commonLabels` support → use `podLabels`/`podAnnotations` for
  that chart only. This is a chart limitation, not a platform choice.

Run to confirm what label keys the chart supports:
```bash
grep -n "commonLabels\|customLabels\|podLabels" services/<name>helm/v1/chart/templates/statefulset.yaml
```

### 3c — Annotations (sovcore keys)
```yaml
commonAnnotations:
  sovcore.byop.ibm.com/crn: {{ context.crn | default("crn:unknown") | yaml_safe }}
  sovcore.byop.ibm.com/account-id: {{ context.account_id | default("unknown") | yaml_safe }}
  sovcore.byop.ibm.com/sub-account-id: {{ context.sub_account_id | default("unknown") | yaml_safe }}
  sovcore.byop.ibm.com/platform: {{ context.platform | default("unknown") | yaml_safe }}
```
- **Always use `commonAnnotations`** for the four `sovcore.byop.ibm.com/*` keys — never an empty `{}`.
- **Never use `customAnnotations`** for BYOP platform metadata. Same reasoning as 3b: it is a
  chart-internal key, not the platform identity channel.

### 3d — Instance block (required for all services)
```yaml
instance:
  name: {{ instance_name }}
  id: "{{ instance_id }}"
  environment: {{ environment }}
  clusterName: "{{ cluster_name }}"
```
Place this block after `commonAnnotations` and before `imagePullSecrets`.
Exception: langfusehelm has no namespace/instance support in the chart — omit.

### 3e — imagePullSecrets format
```yaml
imagePullSecrets:
{% if image_pull_secret_name %}
  - name: {{ image_pull_secret_name }}
{% else %}
  []
{% endif %}
```
- Must use `- name: {{ image_pull_secret_name }}` — **never** bare `- {{ image_pull_secret_name }}`
- Kubernetes expects `{name: ...}` objects; bare strings are silently ignored at runtime
- Exception: HashiCorp Vault chart uses `global.imagePullSecrets` — leave as-is

## Check 4 — SCC settings in chart/values.yaml

The chart `values.yaml` must have these exact defaults (OpenShift `restricted-v2` compatible):

```yaml
podSecurityContext:
  fsGroup: null
  seccompProfile:
    type: RuntimeDefault

securityContext:
  allowPrivilegeEscalation: false
  privileged: false
  readOnlyRootFilesystem: true   # false only if app must write to rootfs
  runAsNonRoot: true
  runAsUser: null
  runAsGroup: null
  capabilities:
    drop:
      - ALL
  seccompProfile:
    type: RuntimeDefault
```

Fix: hardcoded `fsGroup/runAsUser/runAsGroup: 999` → `null`; missing `seccompProfile` → add it.

**The template must NOT contain `podSecurityContext` or `securityContext` blocks.**
If it does, remove them — the chart defaults are the single source of truth.

## Check 5 — image registry/repository split and BYOP_REGISTRY

### chart/values.yaml
Every image block must have a separate `registry` (hostname only) and `repository` (path after hostname):

```yaml
image:
  registry: "docker.io"           # hostname only — no path segments
  repository: "library/redis"     # everything after the hostname
  tag: ""                         # empty = use Chart.AppVersion
  pullPolicy: IfNotPresent
```

- `registry` must be a bare hostname: `docker.io`, `quay.io`, etc. — **never** `docker.io/library` or `quay.io/coreos`
- `repository` carries all path segments after the hostname: `library/redis`, `coreos/etcd`, `valkey/valkey`
- Charts that previously had only `repository: "mariadb"` (no `registry`) need the `registry` field added
- The chart `values.yaml` defaults must be the **source image** (Docker Hub / upstream), not the airgap registry

Verify with:
```bash
grep -n "registry:\|repository:" services/<name>helm/v1/chart/values.yaml
```

### chart/templates/statefulset.yaml (and deployment.yaml)
All image rendering must follow:
```
"{{ .Values.image.registry }}/{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
```

Flag and fix any inline concatenation that embeds `byop/` in the registry field or uses only `repository` without `registry`.

### template/values.yaml.tmpl — BYOP_REGISTRY (mandatory)
The tmpl image block must:
1. Use `BYOP_REGISTRY` as the registry value — this is a **literal placeholder string**, not a hostname.
   It is resolved at deploy time by `service-render --mapping image-mapping.txt` via the line
   `BYOP_REGISTRY -> <hostname>` at the top of `image-mapping.txt`.
   Operators change that single line to target a different air-gap registry. **Never hardcode the hostname.**
2. Set `repository: byop/<image-name>` (all images mirrored under the `byop` org)
3. Pin the exact tag matching `imagesetconfiguration.yaml`

```yaml
image:
  registry: BYOP_REGISTRY
  repository: byop/redis
  tag: "8.8.0"
```

Check that no hardcoded hostname remains:
```bash
grep -r "registry-quay-quay-enterprise" services/<name>helm/v1/template/
```

If any multi-image chart has an init container or sidecar, each image needs its own block following the same pattern.

## Check 6 — imagesetconfiguration.yaml completeness

`imagesetconfiguration.yaml` is the **source of truth** for all images a service needs.
Every image referenced in `values.yaml.tmpl` must have a corresponding entry.

Verify every image block in the tmpl has a matching line:
```bash
grep "repository:" services/<name>helm/v1/template/values.yaml.tmpl
grep "name:" services/<name>helm/v1/imagesetconfiguration.yaml
```

Rules:
- Source refs use Docker Hub / upstream registry (e.g. `docker.io/library/redis:8.8.0`)
- Docker Hub official images use `docker.io/library/<name>:<tag>` (with `library/` prefix)
- Each entry should have a comment `# Latest stable: <ref>` above it noting the current upstream latest
- If a sidecar exporter was added (e.g. `prom/memcached-exporter`), it must be listed here too

## Check 7 — StatefulSet headless service

A StatefulSet's `spec.serviceName` must reference a **headless** service (`clusterIP: None`).
Check what the statefulset declares:
```bash
grep "serviceName:" services/<name>helm/v1/chart/templates/statefulset.yaml
```

Then verify a corresponding headless service template exists:
```bash
ls services/<name>helm/v1/chart/templates/
grep "clusterIP: None" services/<name>helm/v1/chart/templates/
```

If the StatefulSet points to a regular ClusterIP service, either:
- Create `service-headless.yaml` with `clusterIP: None` and update `serviceName` to `<fullname>-headless`

Follow the pattern in `services/memcachedhelm/v1/chart/templates/service-headless.yaml`.

## Check 8 — metrics.json format

Must be valid JSON containing a `metrics` array:
```json
{"metrics": []}
```

Fix with: `echo '{"metrics": []}' > services/<name>helm/v1/catalog/metrics.json`

## Check 9 — values-test.yaml exists and is correct

Every service must have `services/<name>helm/v1/values-test.yaml` for local testing without image substitution.

**Critical rule:** `values-test.yaml` must **never** contain `BYOP_REGISTRY`. It must use the upstream
source registry directly (e.g. `docker.io`) so testing works without an air-gap registry or image mirror.

If missing, create it by resolving all Jinja2 variables in `values.yaml.tmpl` to representative test values:
- `BYOP_REGISTRY` → `docker.io` (upstream source registry — no airgap needed locally)
- `repository: byop/<name>` → `repository: library/<name>` (or upstream org, e.g. `osixia/openldap`)
- `{{ namespace }}` → `<name>-test`
- `{{ storage_size }}` → `1Gi`
- `{{ replicas }}` → `1`
- `{{ spec.* }}` → sensible test defaults matching schema constraints
- `imagePullSecrets: []`
- `storageClass` → `standard` (works on most local clusters)

If present, verify:
- `registry:` value is **not** `BYOP_REGISTRY` — must be `docker.io` or other upstream hostname
- `repository:` value is the upstream path, not `byop/<name>`

Include usage comment at top:
```yaml
# Usage:
#   helm upgrade --install <name>-test services/<name>helm/v1/chart \
#     -f services/<name>helm/v1/values-test.yaml \
#     --create-namespace \
#     --namespace <name>-test
```

## Check 10 — image-mapping.txt entry

`image-mapping.txt` at the repo root maps every source image to its runtime location.
After adding or changing images in `imagesetconfiguration.yaml`, ensure `image-mapping.txt` has a matching line:

```
docker.io/library/<name>:<tag>  ->  localhost:5000/byop/<name>:<tag>
```

The `BYOP_REGISTRY -> localhost:5000` line at the top covers the registry placeholder substitution.

## Check 11 — README.md exists and is accurate

If missing, create it following `services/mariadbhelm/v1/README.md` structure.
If present, verify:
- Chart version matches `chart/Chart.yaml`
- Parameter table matches `catalog/schema.json`
- Helm values table matches `template/values.yaml.tmpl`
- No references to another service's name

## Check 12 — Run the automated validator

Run the full validation suite and report every failing test:

```bash
python3 tools/service-validator --version v1 services/<name>helm
```

Use `execute_command` to run this. Parse the output: each `[PASS]` / `[FAIL]` line maps to a named test.
For every `[FAIL]`, identify the root cause and apply the fix described in the relevant Check above,
then re-run until all 14 tests pass.

Tests 0–13 and what they check:
| # | Name | What it checks |
|---|------|----------------|
| 0 | directory-structure | Required files and directories exist |
| 1 | catalog-yaml | catalog.yaml name field matches directory |
| 2 | schema-json | schema.json is valid JSON |
| 3 | chart-yaml | Chart.yaml has name and appVersion |
| 4 | values-yaml | chart/values.yaml is valid YAML |
| 5 | tmpl-jinja | template/values.yaml.tmpl has no Jinja syntax errors |
| 6 | values-test-exists | values-test.yaml exists |
| 7 | helm-template | `helm template` exits 0 (chart renders without errors) |
| 8 | helm-template-images | All `image:` lines from helm template have no empty segment |
| 9 | scc-keys | chart/values.yaml contains runAsNonRoot, fsGroup: null, seccompProfile |
| 10 | byop-registry | template/values.yaml.tmpl uses BYOP_REGISTRY (not a hardcoded hostname) |
| 11 | service-name | Directory name is lowercase alpha only [a-z]+ and ≤ 22 characters |
| 12 | yaml-safe | Every x-generate field in schema.json has `\| yaml_safe` in the template |
| 13 | no-byop-registry-in-test | values-test.yaml does not contain BYOP_REGISTRY |

All 14 tests must pass before declaring the service fixed and ready.
