# BYOP Broker Deployment Scripts

## Scripts

| Script | Role |
|---|---|
| `deploy-byop-broker.sh` | Orchestrator — checks dependencies, then runs phases 1–4 in order |
| `1-generate-values.sh` | Generate `values-generated.yaml` from environment variables |
| `2-build-images.sh` | Build broker and catalog-app images from source with Podman |
| `3-push-images.sh` | Push broker, catalog-app, MariaDB and MongoDB images to internal Quay |
| `4-deploy-helm.sh` | Deploy the broker Helm chart and wait for rollout |
| `3-mirror-extra-images.sh` | Mirror additional service images (valkey, postgres, mysql, rabbitmq, odoo, keycloak, memcached, redis, nginx, busybox, vault, etcd) — **not called by the orchestrator**, run manually as needed |
| `show-broker-outputs.sh` | Print `BROKER_ROUTE_HOST`, `CATALOG_APP_ROUTE_HOST` — run any time after deployment |

## Dependency checks

| Check | `deploy-byop-broker.sh` | `1-generate-values.sh` | `2-build-images.sh` | `3-push-images.sh` | `4-deploy-helm.sh` |
|---|:---:|:---:|:---:|:---:|:---:|
| **`--source` arg** | ✓ | ✓ | ✓ | | ✓ |
| **`podman`** | ✓ | | ✓ | ✓ | |
| **`helm`** | ✓ | | | | ✓ |
| **`oc`** | ✓ | | | | ✓ |
| **Cluster connectivity** | ✓ | | | | ✓ |
| **`values-generated.yaml` exists** | | | | | ✓ |
| **`QUAY_REGISTRY`** | ✓ | ✓ | | ✓ | |
| **`BYOP_ROBOT_TOKEN`** | ✓ | | | ✓ | |
| **`CLUSTER_DOMAIN`** | ✓ | ✓ | | | |
| **`GITEA_HOST`** | ✓ | ✓ | | | |
| **`GITEA_SSH_PORT`** | ✓ | ✓ | | | |
| **`GITEA_USER_ID`** | ✓ | ✓ | | | |
| **`GITEA_SSH_KEY_PATH`** | ✓ | ✓ | | | |
| **SSH key file exists** | ✓ | ✓ | | | |

> Each script checks its own dependencies so it can run independently.
> When invoked via `deploy-byop-broker.sh`, all checks have already passed.
