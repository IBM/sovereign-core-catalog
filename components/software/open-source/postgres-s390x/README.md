# PostgreSQL for IBM Z / LinuxONE (s390x)

Helm chart and catalog entry for running **PostgreSQL** on **IBM Z and LinuxONE (`linux/s390x`)** nodes, deployed by the **Sovereign Core BYOP broker**.

> **Deployment model.** This chart is deployed exclusively by the Sovereign Core BYOP broker. Instances are provisioned, updated and deleted through the Sovereign Core catalog — do not install, upgrade or uninstall the chart directly with Helm. The only Helm commands used with this chart are the packaging and push steps in [Publishing the chart](#publishing-the-chart).

| | |
|---|---|
| Chart name | `postgres-s390x` |
| Chart version | `1.0.4` (`chart/Chart.yaml` → `version`) |
| App version | `17.11` (`chart/Chart.yaml` → `appVersion`) |
| Container image | `s390x/postgres:17.11` (Docker Hub, official s390x image) |
| Workload | one `StatefulSet` (default 1 replica), headless `Service`, `Secret`, `ConfigMap`, optional Docker Hub pull `Secret` |

Pods are pinned to s390x nodes (`nodeSelector: kubernetes.io/arch: s390x`), data is stored on a `ReadWriteOnce` PersistentVolumeClaim, and `pg_isready` is used for readiness/liveness probes. For chart values and broker integration details, see [`chart/README.md`](chart/README.md).

---

## Contents of this folder

```
postgres-s390x/
├── README.md                  # this file
├── catalog/                   # Sovereign Core catalog definition
│   ├── catalog.yaml           #   display name, description, category, tags
│   ├── metadata.yaml          #   import metadata (sourceType, sourceRepo, sourceVersion, images)
│   ├── schema.json            #   provisioning parameters (JSON Schema)
│   └── metrics.json           #   metrics definition (currently empty)
├── chart/                     # Helm chart source + packaged chart
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── README.md              #   chart-level documentation
│   ├── templates/
│   └── postgres-s390x-1.0.4.tgz   # packaged chart (output of `helm package`)
├── template/
│   └── values.yaml.tmpl       # values template rendered by the Sovereign Core broker
└── v17.11/
    └── metadata.yaml          # SoftwareListing for catalog validation
```

> The `.tgz` in `chart/` is generated from the chart source next to it. After any chart change, regenerate and re-push it (see [Repackaging after a chart change](#repackaging-after-a-chart-change)).

---

## Provisioning via the Sovereign Core catalog

The listing in `catalog/` defines the `PostgreSQL Database s390x` service (category `databases`). Provisioning parameters are defined in [`catalog/schema.json`](catalog/schema.json):

| Parameter | Required | Notes |
|---|---|---|
| `clusterTarget` | yes | ArgoCD cluster name to deploy to |
| `database_name` | yes | Pattern `^[a-zA-Z][a-zA-Z0-9_]*$`, 1–64 characters |
| `database_user` | no | Default `appuser` |
| `database_password` | no | 8–128 characters; auto-generated if not provided |
| `superuser_password` | no | 12–128 characters; auto-generated if not provided |
| `image_pull_secret_name` | no | Name of a pre-existing pull secret in the target namespace |
| `storage_class` | no | StorageClass for the data PVC (`ReadWriteOnce`) |
| `storage_size` | no | Kubernetes quantity, default `10Gi` |

`template/values.yaml.tmpl` maps these parameters to chart values when the broker deploys the chart. Broker behaviour to be aware of:

- Credentials are broker-generated and stored in a Kubernetes `Secret` — they are never written to chart values or Git.
- The image is pulled from the platform's internal mirror (`BYOP_REGISTRY/byop/postgres-s390x`), not Docker Hub.
- The pull secret referenced by `image_pull_secret_name` must already exist in the target namespace — it is created by the platform admin, not by the broker or the chart.

---

## Publishing the chart

You need **Helm 3.8 or later** (for `helm push` / `helm registry login`) and credentials for the Sovereign Core Quay registry (or your chosen OCI registry).

The packaged chart is at `chart/postgres-s390x-1.0.4.tgz`; its name and version derive from `chart/Chart.yaml`. Replace every `<placeholder>` with your own values. **Never commit real credentials** — pass them via environment variables or a secret store.

```bash
export REGISTRY=<quay-host>              # e.g. the Quay host of your Sovereign Core deployment
export NAMESPACE=<org>/<path>            # target repository path in Quay
export QUAY_USERNAME=<username>
export QUAY_PASSWORD=<password-or-robot-token>

# 1. Log in (password via stdin keeps it out of shell history)
echo "$QUAY_PASSWORD" | helm registry login "$REGISTRY" \
  --username "$QUAY_USERNAME" --password-stdin

# 2. Push — Helm appends the chart name, result: oci://$REGISTRY/$NAMESPACE/postgres-s390x:1.0.4
helm push chart/postgres-s390x-1.0.4.tgz "oci://$REGISTRY/$NAMESPACE"

# 3. Verify
helm show chart "oci://$REGISTRY/$NAMESPACE/postgres-s390x" --version 1.0.4
```

If the registry uses a self-signed certificate, prefer `--ca-file` (run `helm push --help` for the TLS flags in your Helm version).

The repository's `scripts/import.sh` pushes charts to `oci://<QUAY_REGISTRY>/sovcloud/cp/sovereign-cloud-platform/byop/charts`. Use that path as `NAMESPACE` to land your manual push in the same location the import pipeline uses; confirm with your Sovereign Core administrator.

---

## Repackaging after a chart change

1. Edit the chart under `chart/` (templates, `values.yaml`, ...).
2. **Bump `version`** in `chart/Chart.yaml` (and `appVersion` if the PostgreSQL version changes). A registry will not accept a different chart under an existing version.
3. Lint and render:
   ```bash
   helm lint chart
   helm template test chart > /dev/null
   ```
4. Rebuild the package from this folder (`postgres-s390x/`):
   ```bash
   rm -f chart/postgres-s390x-*.tgz
   helm package chart --destination chart
   ```
5. Verify: `helm show chart chart/postgres-s390x-<new-version>.tgz`.
6. Keep these in sync with the new version:
   - `catalog/metadata.yaml` → `sourceVersion`
   - `catalog/metadata.yaml` / `v17.11/metadata.yaml` → image tag / `version` if the PostgreSQL version changed
   - `template/values.yaml.tmpl` → `image.tag` if the PostgreSQL version changed
7. Push the new `.tgz` (see [Publishing the chart](#publishing-the-chart)).

---

## Notes

- `catalog/metadata.yaml` sets `sourceRepo: oci://quay.io/postgreshelm/postgres-s390x` and `sourceVersion: "1.0.4"`. `scripts/import.sh` pulls the chart from there, so push the chart to that location (or update `sourceRepo`) before importing the listing.
- `helm lint` reports one informational message (`icon is recommended`) because `Chart.yaml` has no `icon`; it is not an error.
