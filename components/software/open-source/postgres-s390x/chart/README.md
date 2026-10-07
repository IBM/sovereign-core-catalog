# PostgreSQL s390x Helm Chart

This Helm chart deploys a PostgreSQL instance on IBM Z and LinuxONE (**s390x**) nodes using the official [`s390x/postgres`](https://hub.docker.com/r/s390x/postgres) Docker image.

The chart is designed to integrate with the Sovereign Core catalog broker (`byop-broker`) and follows the same conventions as other charts in this repository (MariaDB, etcd, etc.).

## Key differences from the standard `postgres` catalog entry

| Feature | `postgres` (x86) | `postgres-s390x` |
|---|---|---|
| Image | Bitnami `oci://registry-1.docker.io/bitnamicharts/postgresql` | Official `s390x/postgres:17.11` |
| Architecture | `linux/amd64` | `linux/s390x` |
| Node scheduling | No restriction | `nodeSelector: kubernetes.io/arch: s390x` |
| Deployment type | Bitnami chart (external) | Custom Helm chart (this repo) |

## Installation

```bash
helm install my-postgres ./chart \
  --set auth.superuserPassword=<SUPERUSER_PW> \
  --set auth.password=<APP_PW> \
  --set auth.database=mydb \
  --set auth.username=myuser
```

## Configuration

| Parameter | Description | Default |
|---|---|---|
| `image.repository` | Container image | `s390x/postgres` |
| `image.tag` | Image tag (PostgreSQL version) | `17.11` |
| `auth.superuserPassword` | PostgreSQL superuser (`postgres`) password | `change-me-superuser-password` |
| `auth.database` | Application database name | `appdb` |
| `auth.username` | Application database user | `appuser` |
| `auth.password` | Application user password | `change-me-password` |
| `persistence.enabled` | Enable persistent storage via PVC | `true` |
| `persistence.size` | PVC storage size | `1Gi` |
| `statefulset.replicas` | Number of replicas | `1` |
| `pgConfig` | Extra key/value PostgreSQL config settings | `{}` |

## Node scheduling

The `statefulset.yaml` enforces:

```yaml
nodeSelector:
  kubernetes.io/arch: s390x
```

This guarantees the pod lands on an IBM Z / LinuxONE node in a heterogeneous cluster.

## Probes

Both `readinessProbe` and `livenessProbe` use `pg_isready`, which is included in the official PostgreSQL image and avoids any shell-level authentication complexity.

## Uninstallation

```bash
helm uninstall my-postgres
```

## Made with Bob
