---
name: new-olm-service-mirroring
description: Use when the user wants to add oc-mirror mirroring configuration for an OLM operator (OperatorHub bundle) into an existing or new service definition — covers ImageSetConfiguration operators stanza, catalog source, ICSP/IDMS, and validation steps.
---

# new-olm-service-mirroring

Add `oc-mirror` mirroring configuration for an OLM operator bundle into a service definition.
This is for **OLM operators** (OperatorHub bundles with CatalogSource + CSV), not plain container
images. Plain images use the `additionalImages:` stanza and are covered by `new-helm-service`.

## Step 1 — Identify the operator

Collect:
- **Package name** — the OperatorHub package name, e.g. `elasticsearch-eck-operator-certified`
- **Channel** — the subscription channel, e.g. `stable`, `fast`, `alpha`
- **Catalog source** — which index image to mirror from:
  - Red Hat: `registry.redhat.io/redhat/redhat-operator-index:v4.XX`
  - Certified: `registry.redhat.io/redhat/certified-operator-index:v4.XX`
  - Community: `registry.redhat.io/redhat/community-operator-index:v4.XX`
- **Target OpenShift version** — determines the index image tag (`v4.14`, `v4.15`, `v4.16`, …)
- **Min/max version range** (optional) — pin to a specific CSV version or let oc-mirror pick latest

Find the exact package name if unsure:
```bash
# Render the catalog index to list available packages (requires oc-mirror and registry access)
oc-mirror list operators --catalog registry.redhat.io/redhat/redhat-operator-index:v4.15
```

## Step 2 — Write the ImageSetConfiguration operators stanza

OLM operators use the `operators:` key, not `additionalImages:`. Add to
`services/<name>/v1/imagesetconfiguration.yaml`:

```yaml
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v1alpha2
storageConfig:
  local:
    path: ./metadata
mirror:
  operators:
    - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.15
      packages:
        - name: elasticsearch-eck-operator-certified
          channels:
            - name: stable
          # Optional: pin to a specific version range
          # minVersion: "2.9.0"
          # maxVersion: "2.12.0"
```

Rules:
- Use the **full catalog ref** including the OCP version tag — do not use `latest`
- Specify `channels` explicitly — do not rely on the default channel in the index
- If pinning a version range, test that `minVersion`/`maxVersion` exist in the catalog first
- If the operator needs multiple channels, add each as a separate entry under `channels:`

## Step 3 — Run oc-mirror (dry run first)

Always dry-run before a real mirror to verify the package/channel exists and estimate size:

```bash
# Dry run — validates config, prints what would be mirrored, no writes
oc-mirror --config services/<name>/v1/imagesetconfiguration.yaml \
  docker://localhost:5000 \
  --dry-run 2>&1 | tee /tmp/oc-mirror-dryrun.log

# Check for package-not-found errors
grep -i "error\|not found\|no such" /tmp/oc-mirror-dryrun.log
```

If dry-run fails with `package not found`:
1. Verify the package name: `oc-mirror list operators --catalog <catalog-ref> | grep <partial-name>`
2. Verify the channel exists: `oc-mirror list operators --catalog <catalog-ref> --package <pkg-name>`
3. Check the OCP version tag — some operators are only in newer index versions

## Step 4 — Run the real mirror

```bash
oc-mirror --config services/<name>/v1/imagesetconfiguration.yaml \
  docker://<AIRGAP_REGISTRY>/byop/<name>/mirror
```

This produces a `oc-mirror-workspace/` directory containing:
- `mapping.txt` — source → dest image map
- `catalogSource-*.yaml` — CatalogSource to apply in the airgap cluster
- `imageContentSourcePolicy.yaml` or `imageDigestMirrorSet.yaml` — mirror routing rules

## Step 5 — Apply mirror artefacts to the cluster

```bash
# Apply the CatalogSource (makes the operator visible in OperatorHub on the airgap cluster)
oc apply -f oc-mirror-workspace/results-*/catalogSource-*.yaml

# Apply the mirror routing rules (tells OCP to pull from the mirror)
# OCP 4.13+: use IDMS
oc apply -f oc-mirror-workspace/results-*/imageDigestMirrorSet.yaml
# OCP <4.13: use ICSP
# oc apply -f oc-mirror-workspace/results-*/imageContentSourcePolicy.yaml

# Wait for nodes to apply the new MachineConfig (ICSP/IDMS triggers a node reload)
oc wait mcp master worker --for condition=Updated --timeout=600s
```

## Step 6 — Verify operator availability

```bash
# Confirm the CatalogSource is READY
oc get catalogsource -n openshift-marketplace

# Confirm the package appears in OperatorHub
oc get packagemanifest <package-name> -n openshift-marketplace -o yaml | \
  grep -E "currentCSV|channel|catalogSource"
```

## Step 7 — Update image-mapping.txt

OLM operators are not listed individually in `image-mapping.txt` (the mapping is managed by
`oc-mirror`'s `mapping.txt` output). However, add a comment block so operators know this
service uses OLM mirroring:

```
# <name> — OLM operator, mirrored via oc-mirror
# See services/<name>/v1/imagesetconfiguration.yaml operators stanza
# Catalog: registry.redhat.io/redhat/redhat-operator-index:v4.15
# Package: <package-name>  Channel: <channel>
```

## Step 8 — Validate

```bash
# Confirm the imagesetconfiguration.yaml is valid YAML
python3 -c "import yaml; yaml.safe_load(open('services/<name>/v1/imagesetconfiguration.yaml'))" && echo OK

# Confirm operators stanza is present (not additionalImages)
grep -c "operators:" services/<name>/v1/imagesetconfiguration.yaml
```

## Key differences: OLM operators vs plain images

| | Plain images (`additionalImages`) | OLM operators (`operators`) |
|---|---|---|
| Stanza | `mirror.additionalImages` | `mirror.operators` |
| Source | Any registry | Red Hat catalog index image |
| Output artefacts | Mirrored blobs only | Blobs + CatalogSource + ICSP/IDMS |
| Cluster config needed | None | CatalogSource + ICSP/IDMS applied |
| Version pin | `:tag` in image ref | `minVersion`/`maxVersion` in stanza |
| `image-mapping.txt` | One line per image | Comment block only |
