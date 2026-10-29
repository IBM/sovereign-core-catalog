# PostgreSQL s390x Helm Chart

Deploys a PostgreSQL instance on IBM Z and LinuxONE (**s390x**) nodes using the official [`s390x/postgres`](https://hub.docker.com/r/s390x/postgres) image. Requires a cluster with s390x worker nodes and a `ReadWriteOnce`-capable StorageClass.

The chart is deployed by the Sovereign Core catalog broker (`byop-broker`); it is not installed directly with Helm. Packaging and push instructions are in the component README (`postgres-s390x/README.md` in the catalog repository).

---

## Configuration reference

| Parameter | Description | Default |
|---|---|---|
| `image.registry` | Optional registry prefix (e.g. internal mirror) | `""` |
| `image.repository` | Container image repository | `s390x/postgres` |
| `image.tag` | PostgreSQL image tag | `17.11` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `imagePullSecrets` | Names of pre-existing pull secrets; the broker populates this from the `image_pull_secret_name` provisioning parameter | `[]` |
| `dockerhubPullSecret.create` | Let the chart create a Docker Hub pull secret. Hardcoded to `false` in broker deployments | `false` |
| `dockerhubPullSecret.secretName` / `dockerServer` / `dockerUsername` / `dockerPassword` / `dockerEmail` | Settings for the chart-created pull secret | `dockerhub-pull-secret` / `docker.io` / `""` |
| `auth.superuserPassword` | PostgreSQL superuser (`postgres`) password | `change-me-superuser-password` (placeholder) |
| `auth.database` | Application database name | `appdb` |
| `auth.username` | Application database user | `appuser` |
| `auth.password` | Application user password | `change-me-password` (placeholder) |
| `persistence.enabled` | Enable PVC for the data volume | `true` |
| `persistence.size` | PVC storage size | `1Gi` |
| `persistence.storageClass` | StorageClass name (empty = cluster default) | `""` |
| `persistence.accessModes` | PVC access modes | `[ReadWriteOnce]` |
| `statefulset.replicas` | Number of replicas | `1` |
| `service.port` | PostgreSQL service and container port | `5432` |
| `service.clusterIP` | Service `clusterIP` (`None` = headless) | `None` |
| `container.resources` | CPU / memory requests and limits | `{}` |
| `probes.readiness.*` / `probes.liveness.*` | `initialDelaySeconds` / `periodSeconds` / `timeoutSeconds` | `30`/`60`, `10`, `5` |
| `pgConfig` | Extra key/value pairs written into the ConfigMap. They are **not** mounted as `postgresql.conf` and do not change server settings in this chart version | `{}` |
| `instance.name` | Instance name used in resource names (`postgres-s390x-<name>`); falls back to the Helm release name | `""` |
| `instance.id`, `instance.environment`, `instance.clusterName` | Labels / annotations metadata | `""` |
| `namespaceOverride` | Namespace written into manifests | `""` |
| `database_name`, `database_user`, `database_password`, `superuser_password`, `storage_class`, `storage_size`, `instanceName` | Flat values passed by the broker. When set they take precedence over `auth.*`, `persistence.*` and `instance.name` | unset |

`nameOverride`, `fullnameOverride` and `podSecurityContext` exist in `values.yaml` but are not used by the current templates.

The chart creates a `Secret` named `postgres-s390x-<instance>` holding `superuser-password`, `username`, `password`, `database`, `connection-string` and `jdbc-url`. Inside the cluster the database is reachable at `postgres-s390x-<instance>.<namespace>.svc:5432`.

---

## Broker deployment behaviour (byop-broker)

The broker renders `template/values.yaml.tmpl` into a Helm values override and deploys the chart with it:

- Credentials are broker-generated and passed via `auth.*`; they are never written to the values file or Git.
- `dockerhubPullSecret.create` is **hardcoded to `false`** — the chart never creates a pull secret in a broker deployment. The pull secret name comes from the `image_pull_secret_name` provisioning parameter (`catalog/schema.json`).
- The pull secret must already exist in the target namespace — it is created by the platform admin, not by the broker or the chart. If it is missing, the pod fails with `ErrImagePull`.
- The image repository is rewritten to the platform's internal mirror (`BYOP_REGISTRY/byop/postgres-s390x`); Docker Hub is not contacted in a broker deployment.

---

## Node scheduling

`statefulset.yaml` enforces `nodeSelector: kubernetes.io/arch: s390x`, so the pod only schedules on IBM Z / LinuxONE nodes. If the cluster has no schedulable s390x nodes, the pod stays `Pending`.

## OpenShift volume permissions

The official `s390x/postgres` image expects to own its data directory as uid/gid 999 (`postgres`). The chart sets `PGDATA=/var/lib/postgresql/data/pgdata` (a subdirectory of the mount, so `lost+found` does not break `initdb`), renders an empty pod `securityContext` and ships no initContainer. Volume ownership therefore depends on the cluster's SCC / storage driver.
