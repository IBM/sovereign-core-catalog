# ArgoCD Deployment Scripts

## Scripts

| Script | Role |
|---|---|
| `deploy-argocd.sh` | Orchestrator — checks dependencies, then runs phases 1–5 in order |
| `1-mirror-images.sh` | Mirror ArgoCD and Redis images from public registries to internal Quay |
| `2-install-argocd.sh` | Install ArgoCD into the cluster and wait for the server rollout |
| `3-configure-repo.sh` | Register the Gitea SSH repository in ArgoCD |
| `4-register-known-hosts.sh` | Add the Gitea SSH host key to ArgoCD's `known_hosts` ConfigMap |
| `5-restart-argocd.sh` | Restart the ArgoCD server to use the updated `known_hosts` |
| `show-argocd-outputs.sh` | Print `ARGOCD_ROUTE_HOST`, `ARGOCD_ADMIN_PASSWORD` — run any time after deployment |

## Dependency checks

| Check | `deploy-argocd.sh` | `1-mirror-images.sh` | `2-install-argocd.sh` | `3-configure-repo.sh` | `4-register-known-hosts.sh` | `5-restart-argocd.sh` |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| **`--source` arg** | ✓ | | ✓ | ✓ | | |
| **`podman`** | ✓ | ✓ | | | | |
| **`oc`** | ✓ | | ✓ | ✓ | ✓ | ✓ |
| **`ssh-keyscan`** | ✓ | | | | ✓ | |
| **`python3`** | ✓ | | | | ✓ | |
| **Cluster connectivity** | ✓ | | ✓ | ✓ | ✓ | ✓ |
| **`QUAY_REGISTRY`** | ✓ | ✓ | ✓ | | | |
| **`ARGOCD_ROBOT_TOKEN`** | ✓ | ✓ | | | | |
| **`GITEA_HOST`** | ✓ | | | ✓ | ✓ | |
| **`GITEA_SSH_PORT`** | ✓ | | | ✓ | ✓ | |
| **`GITEA_USER_ID`** | ✓ | | | ✓ | | |
| **`GITEA_SSH_KEY_PATH`** | ✓ | | | ✓ | | |
| **SSH key file exists** | ✓ | | | ✓ | | |

> Individual scripts keep their own checks so they can be run standalone.
> When invoked via `deploy-argocd.sh`, all checks have already passed.
