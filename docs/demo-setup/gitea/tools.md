# Gitea Deployment Scripts

## Scripts

| Script | Role |
|---|---|
| `deploy-gitea.sh` | Orchestrator — checks dependencies, runs phases 1–6, and prints `GITEA_HOST` / `GITEA_SSH_PORT` / `GITEA_USER_ID` |
| `1-generate-values.sh` | Generate `values-generated.yaml` from environment variables |
| `2-mirror-images.sh` | Mirror Gitea, Postgres and Redis images to internal Quay |
| `3-deploy-helm.sh` | Deploy the Gitea Helm chart and wait for rollout |
| `4-create-admin-user.sh` | Create the `gitops` admin user inside the Gitea pod |
| `5-add-ssh-key.sh` | Register the SSH public key for the `gitops` user via Gitea API |
| `6-create-repo.sh` | Create the `gitops` repository via Gitea API |
| `show-gitea-outputs.sh` | Print `GITEA_HOST`, `GITEA_SSH_PORT`, `GITEA_USER_ID`, `GITEA_ROUTE_HOST` — run any time after deployment |

## Dependency checks

| Check | `deploy-gitea.sh` | `1-generate-values.sh` | `2-mirror-images.sh` | `3-deploy-helm.sh` | `4-create-admin-user.sh` | `5-add-ssh-key.sh` | `6-create-repo.sh` |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **`--source` arg** | ✓ | ✓ | | ✓ | | | |
| **`podman`** | ✓ | | ✓ | | | | |
| **`helm`** | ✓ | | | ✓ | | | |
| **`oc`** | ✓ | | | ✓ | ✓ | | |
| **`curl`** | ✓ | | | | | ✓ | ✓ |
| **Cluster connectivity** | ✓ | | | ✓ | ✓ | | |
| **`values-generated.yaml` exists** | | | | ✓ | | | |
| **`GITEA_POD`** (resolved live) | ✓ | | | | ✓ | | |
| **`QUAY_REGISTRY`** | ✓ | ✓ | ✓ | | | | |
| **`GITEA_ROBOT_TOKEN`** | ✓ | | ✓ | | | | |
| **`CLUSTER_DOMAIN`** | ✓ | ✓ | | | | ✓ | ✓ |
| **`GITEA_PASSWORD`** | ✓ | ✓ | | | ✓ | ✓ | ✓ |
| **`GITEA_EMAIL`** | ✓ | | | | ✓ | | |
| **`GITEA_SSH_KEY_PATH`** | ✓ | | | | | ✓ | |
| **SSH private key file exists** | ✓ | | | | | | |
| **SSH public key file exists** | ✓ | | | | | ✓ | |

> `GITEA_POD` is never passed between scripts — each script that needs it resolves it
> each time with `oc get pod`. This avoids stale references if the pod is rescheduled.
>
> Individual scripts keep their own checks so they can be run standalone.
> When invoked via `deploy-gitea.sh`, all checks have already passed.
