---
name: new-helm-service
description: Use when the user wants to create or scaffold a new Helm-based service definition in this repository — guides through gathering image/version info, running the scaffold script, then filling in catalog, schema, values template, imagesetconfiguration, image-mapping entry, chart image defaults, values-test.yaml, and README.
---

# new-helm-service

Scaffold and complete a new Helm service definition under `services/<name>helm/v1/`.
Follow these steps in order. Do not skip steps — each feeds into the next.

## Step 1 — Gather requirements

Use `ask_followup_question` to collect:
- **Service name** — becomes the directory `services/<name>helm/`
  - ⚠️ `<name>` must be **lowercase alphabetic only** `[a-z]+` and **≤ 22 characters**
  - The broker constructs the Helm release name as `<name>helm-<uuid>` (63 chars total); digits, hyphens, and other non-alpha characters are forbidden
- **Source image** — full upstream reference e.g. `docker.io/library/redis:8.8.0` or `docker.io/valkey/valkey:9.0.4`
- **What parameters** the user wants to expose (password? database name? replicas?)
- **Does the chart already exist** in `services/<name>helm/v1/chart/` or does it need to be sourced?
- **Does it need a sidecar exporter** for Prometheus metrics?

If the chart already exists, read its `values.yaml` and `Chart.yaml` before proceeding — the keys used there
(`commonLabels`, `commonAnnotations`, `storage.*`, auth fields, etc.) are ground truth.

## Step 2 — Run the scaffold script

Use `execute_command` to run the Python scaffolder. It generates all platform wrapper files
with real values already filled in from the image reference — no PLACEHOLDER replacement needed.

```bash
python3 .bob/skills/new-helm-service/scaffold.py \
    --name    <name> \
    --image   <registry>/<repository>:<tag> \
    --display "<Display Name>"
```

Example:
```bash
python3 .bob/skills/new-helm-service/scaffold.py \
    --name    openldap \
    --image   docker.io/osixia/openldap:2.6.15-alpha \
    --display "OpenLDAP Directory"
```

**What gets created** (platform wrapper files only — the Helm chart is imported separately in Step 5):
- `catalog/metrics.json` — static, always identical
- `catalog/catalog.yaml` — filled with name, display name, description, plan IDs
- `catalog/schema.json` — skeleton with `cluster_url`; extend in Step 4
- `argocd/applicationset-helm.yaml.tmpl` — copied verbatim; uses uppercase `SERVICE_NAME` macros
- `imagesetconfiguration.yaml` — filled with the upstream image ref
- `template/values.yaml.tmpl` — standard header + image block; extend in Step 8 after chart import
- `values-test.yaml` — resolved header + upstream image; extend in Step 11 after chart import
- `chart/templates/` — empty stub directory

> The bash fallback `scaffold.sh` is still available if Python/Jinja2 is unavailable, but it
> produces PLACEHOLDER strings that must all be replaced manually.

## Step 3 — Fill in catalog/catalog.yaml

Replace every `PLACEHOLDER` with service-specific values:
- `name` — catalog identifier (e.g. `redishelm`)
- `display_name` — human-readable (e.g. `Redis Cache`)
- `description` — Full-lifecycle <service> service with broker-generated credentials stored in Git, deployed with Helm
- Plan `id` — `<name>helm_plan`

## Step 4 — Fill in catalog/schema.json

Start from `cluster_url` (always present, never required). Add one property per user-facing
parameter following the pattern in `services/redishelm/v1/catalog/schema.json`:
- `password`-style params: `x-generate` block, `minLength: 8`
- `database_name`-style params: `pattern`, `minLength`, `maxLength`
- No database concept (etcd, valkey): just `cluster_url` + credential params
- Set `required: []` unless a param truly has no sensible default

> ⚠️ **`x-generate` + `yaml_safe` rule:** Any field with an `x-generate` block uses the
> `alphanumeric-symbols` charset which includes `{` and `}`. Helm treats `{` as a template
> delimiter and silently drops the entire key if these characters appear in the value.
> Every `x-generate` field **MUST** be rendered with `| yaml_safe` in `values.yaml.tmpl`:
> ```yaml
> myPassword: {{ spec.my_password | yaml_safe }}
> ```

## Step 5 — Fix chart/values.yaml image defaults and SCC

### Image block
Every image in the chart must use a split `registry` (hostname only) + `repository` (path after hostname):

```yaml
image:
  registry: "docker.io"           # hostname only — no path segments
  repository: "library/redis"     # everything after the hostname, matching imagesetconfiguration.yaml
  tag: ""                         # empty = falls back to Chart.AppVersion
  pullPolicy: IfNotPresent
```

- `registry` = bare hostname: `docker.io`, `quay.io` — never `docker.io/library`
- `repository` = all path segments after hostname: `library/redis`, `coreos/etcd`, `valkey/valkey`
- Default values must be the **upstream source** image, not the airgap registry
- If the chart has secondary images (init container, sidecar), each needs its own block with the same split

### SCC defaults
Apply these so the chart is OpenShift `restricted-v2` compatible:

```yaml
podSecurityContext:
  fsGroup: null
  seccompProfile:
    type: RuntimeDefault

securityContext:
  allowPrivilegeEscalation: false
  privileged: false
  readOnlyRootFilesystem: true   # false only if the app must write to rootfs (e.g. Odoo)
  runAsNonRoot: true
  runAsUser: null
  runAsGroup: null
  capabilities:
    drop:
      - ALL
  seccompProfile:
    type: RuntimeDefault
```

Replace any hardcoded `fsGroup/runAsUser/runAsGroup: 999` with `null`.
These must live in the **chart**, not in the template.

## Step 6 — Fix chart/templates image rendering

All image references in `statefulset.yaml` / `deployment.yaml` must use:
```
"{{ .Values.image.registry }}/{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
```

Never use only `repository` without `registry`. If the chart previously had no `registry` field,
add it to `values.yaml` and update the template expression.

Add a `<chart>.image` helper in `_helpers.tpl` (see `services/memcachedhelm/v1/chart/templates/_helpers.tpl`)
and use `{{ include "<chart>.image" . }}` instead of inline concatenation where possible.

## Step 7 — Verify StatefulSet headless service

The StatefulSet `spec.serviceName` must reference a headless service (`clusterIP: None`).
Follow the pattern in `services/memcachedhelm/v1/chart/templates/service-headless.yaml`:
- Name: `<fullname>-headless`
- `clusterIP: None`
- `publishNotReadyAddresses: true`

The regular ClusterIP service stays for client access. Do not remove it.

## Step 8 — Fill in template/values.yaml.tmpl

Every template must open with this standard header in this exact order:

```yaml
# Helm values override for <Service> instance
namespaceOverride: {{ namespace }}

commonLabels:
  app: <service-name>
  service-type: <service-name>

commonAnnotations:
  sovcore.byop.ibm.com/crn: {{ context.crn | default("crn:unknown") | yaml_safe }}
  sovcore.byop.ibm.com/account-id: {{ context.account_id | default("unknown") | yaml_safe }}
  sovcore.byop.ibm.com/sub-account-id: {{ context.sub_account_id | default("unknown") | yaml_safe }}
  sovcore.byop.ibm.com/platform: {{ context.platform | default("unknown") | yaml_safe }}

instance:
  name: {{ instance_name }}
  id: "{{ instance_id }}"
  environment: {{ environment }}
  clusterName: "{{ cluster_name }}"

imagePullSecrets:
{% if image_pull_secret_name %}
  - name: {{ image_pull_secret_name }}
{% else %}
  []
{% endif %}
```

Key rules:
- **Always** use `commonLabels` and `commonAnnotations` — **never** `customLabels` or `customAnnotations`
- `commonAnnotations` must include all 4 `sovcore.byop.ibm.com/*` keys — never an empty `{}`
- `instance:` block is required for all services
- `imagePullSecrets` must use `- name: {{ image_pull_secret_name }}` — **never** a bare `- {{ image_pull_secret_name }}`
- Never put `podSecurityContext` or `securityContext` in the template — those live in the chart
- `fullnameOverride: "{{ service_type }}-{{ instance_id[:8] }}"` — recommended for services with
  subcharts (always use it), optional for simple single-image services

**Known chart exceptions** (document these in a comment if applicable):
- `otwld/ollama-helm` — no `commonLabels` support → use `podLabels`/`podAnnotations` instead
- `HashiCorp Vault` chart — uses `global.namespace` instead of `namespaceOverride`; `global.imagePullSecrets` instead of top-level

Verify what label/annotation keys the chart supports:
```bash
grep -n "commonLabels\|customLabels\|podLabels" services/<name>helm/v1/chart/templates/statefulset.yaml
```

### Image block — use BYOP_REGISTRY placeholder

```yaml
image:
  registry: BYOP_REGISTRY
  repository: byop/<image-name>
  tag: "<pinned-tag>"
```

- `BYOP_REGISTRY` is a **literal string** — `service-render --mapping image-mapping.txt` substitutes
  it with the actual airgap hostname via the `BYOP_REGISTRY -> <hostname>` line in `image-mapping.txt`
- To target a different registry, change that single line in `image-mapping.txt`
- `repository` is always `byop/<name>` — all images are mirrored under the `byop` org
- **Never** hardcode a registry hostname in the tmpl
- If the chart has secondary images (init container, sidecar exporter), add matching blocks for each

Map each `schema.json` property to a `spec.<property>` reference. Apply `| yaml_safe` to every
`x-generate` field (see Step 4 rule).

## Step 9 — Fill in imagesetconfiguration.yaml

`imagesetconfiguration.yaml` is the source of truth for all images this service needs to mirror.
List every image referenced in `values.yaml.tmpl`:

```yaml
mirror:
  additionalImages:
    # Latest stable: docker.io/library/<name>:<latest>
    - name: docker.io/library/<name>:<pinned-tag>
```

Rules:
- Use the upstream source reference (Docker Hub), not the airgap mirror
- Docker Hub official images: `docker.io/library/<name>:<tag>` (with `library/` prefix)
- Non-official images: `docker.io/<org>/<name>:<tag>` or `quay.io/<org>/<name>:<tag>`
- Add one entry per image including any sidecar exporter
- Add `# Latest stable: <ref>` comment above each pinned entry

Check the latest stable tag from Docker Hub:
```bash
curl -sf "https://hub.docker.com/v2/repositories/library/<image>/tags?page_size=50&ordering=last_updated" | \
  python3 -c "import sys,json,re; d=json.load(sys.stdin); print([t['name'] for t in d['results'] if re.match(r'^\d+\.\d+(\.\d+)?$',t['name'])][0])"
```

## Step 10 — Add entry to image-mapping.txt

Add a line per image to the repo-root `image-mapping.txt`, grouped under a comment for the service:

```
# <name>helm
docker.io/library/<name>:<tag>  ->  localhost:5000/byop/<name>:<tag>
```

The `BYOP_REGISTRY -> localhost:5000` line at the top resolves the placeholder for local testing.
**For production deployments**, the operator changes `BYOP_REGISTRY -> localhost:5000` to
`BYOP_REGISTRY -> <real-airgap-hostname>` — no other file changes are needed.

## Step 11 — Create values-test.yaml

Create `services/<name>helm/v1/values-test.yaml` — a static resolved version of `values.yaml.tmpl`
for local testing without image substitution or broker involvement.

> ⚠️ **`values-test.yaml` must never contain `BYOP_REGISTRY`** — use the upstream source registry
> directly so the file works without an air-gap registry.

Resolve all Jinja2 variables to representative test values:
- `image.registry` → `docker.io` (upstream source — **not** `BYOP_REGISTRY`)
- `image.repository` → `library/<name>` or upstream org path (not `byop/<name>`)
- `{{ namespace }}` → `<name>-test`
- `{{ storage_size }}` → `1Gi`
- `{{ replicas }}` → `1`
- `{{ spec.* }}` → sensible defaults respecting schema constraints (min lengths, patterns)
- `imagePullSecrets: []`
- `storageClass` → `standard` (works on most local clusters including kind/k3d)

Include a usage comment at the top:
```yaml
# Usage:
#   helm upgrade --install <name>-test services/<name>helm/v1/chart \
#     -f services/<name>helm/v1/values-test.yaml \
#     --create-namespace \
#     --namespace <name>-test
```

Validate it renders:
```bash
helm template <name>-test services/<name>helm/v1/chart \
  -f services/<name>helm/v1/values-test.yaml 2>&1 | grep "image:"
```

Confirm rendered image refs are complete (no empty registry, no empty tag).

## Step 12 — Write the README.md

Follow the structure of `services/redishelm/v1/README.md` exactly:
1. Title + one-line description
2. Directory structure tree (with chart version from Chart.yaml)
3. Instance parameters table (from schema.json)
4. Key Helm values table (from values.yaml.tmpl)
5. ApplicationSet variables table (SERVICE_NAME, SERVICE_VERSION, SERVICE_TYPE, ARGOCD_NAMESPACE, ARGOCD_PROJECT, GITOPS_REPO_URL, GITOPS_REPO_REVISION, CLUSTER_SERVER)
6. Instance directory layout

## Step 13 — Validate

Run the service validator — all 14 tests must pass:

```bash
python3 tools/service-validator --version v1 services/<name>helm
```

| Test | What it checks |
|------|----------------|
| 0  | Version directory exists |
| 1  | catalog.yaml well-formed (required fields + plans) |
| 2  | metrics.json valid JSON with metrics array |
| 3  | schema.json valid JSON Schema |
| 4  | schema.json properties referenced in template |
| 5  | ArgoCD ApplicationSet descriptor valid |
| 6  | values-test.yaml exists |
| 7  | helm template renders without errors |
| 8  | image: lines complete after helm template -f values-test.yaml |
| 9  | chart/values.yaml has SCC keys (runAsNonRoot, fsGroup: null, seccompProfile) |
| 10 | template/values.yaml.tmpl uses BYOP_REGISTRY (no hardcoded hostname) |
| 11 | Service name is [a-z]+ and ≤ 22 characters |
| 12 | x-generate fields use \| yaml_safe in template |
| 13 | values-test.yaml does not contain BYOP_REGISTRY |

Fix any failures before declaring done.
