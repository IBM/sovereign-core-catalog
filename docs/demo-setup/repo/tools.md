# GitOps Repository Setup Scripts

## Scripts

| Script | Role |
|---|---|
| `deploy-gitops.sh` | Orchestrator — checks dependencies, then runs phases 1–5 in order |
| `1-clone-repo.sh` | Clone the gitops repository from Gitea via SSH |
| `2-extract-content.sh` | Extract service definitions from `archive/sample.tar.gz` into the repo |
| `3-create-image-mapping.sh` | Write `image-mapping.txt` with the internal Quay registry |
| `4-create-helper-scripts.sh` | Write the `pull`, `push`, `render`, `list`, and `reginfo` convenience scripts into the repo |
| `5-commit-and-push.sh` | Commit all changes and push to Gitea |

## Dependency checks

| Check | `deploy-gitops.sh` | `1-clone-repo.sh` | `2-extract-content.sh` | `3-create-image-mapping.sh` | `4-create-helper-scripts.sh` | `5-commit-and-push.sh` |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| **`--target-dir` arg** | ✓ | ✓ | | | | |
| **`--repo-dir` arg** | | | ✓ | ✓ | ✓ | ✓ |
| **`git`** | ✓ | ✓ | | | | ✓ |
| **`tar`** | ✓ | | ✓ | | | |
| **`archive/sample.tar.gz` exists** | ✓ | | ✓ | | | |
| **SSH key file exists** | ✓ | ✓ | | | ✓ | ✓ |
| **`BYOP_REGISTRY`** | ✓ | | | ✓ | | |
| **`GITEA_HOST`** | ✓ | ✓ | | | ✓ | |
| **`GITEA_SSH_PORT`** | ✓ | ✓ | | | ✓ | |
| **`GITEA_USER_ID`** | ✓ | ✓ | | | ✓ | |
| **`GITEA_SSH_KEY_PATH`** | ✓ | ✓ | | | ✓ | ✓ |

> `--repo-dir` is the cloned directory passed from the orchestrator to phases 2–5.
> Each phase can be run standalone by pointing `--repo-dir` at an existing clone.
>
> Individual scripts keep their own checks so they can be run standalone.
> When invoked via `deploy-gitops.sh`, all checks have already passed.

---

## Helper scripts in `repo/gitops`

Phase 4 writes the following convenience scripts into the root of the cloned `repo/gitops` directory. All delegate to the corresponding binary in `tools/`.

| Script | Usage | Description |
|--------|-------|-------------|
| `pull` | `./pull` | `git pull` over SSH using the configured Gitea key |
| `push` | `./push` | `git push` over SSH using the configured Gitea key |
| `render` | `./render <name>helm/v1` | Renders a service: replaces `BYOP_REGISTRY` and image references, generates the ArgoCD ApplicationSet, sets the `latest` symlink |
| `list` | `./list` | Lists all services with their version, rendered status, and active (`latest`) status |
| `reginfo` | `./reginfo <name>helm` | Extracts broker registration info from the active release: name, description, base64 schema, metrics |

### Examples

```bash
# See which services are rendered and active
./list

# Get broker registration payload for a specific service
./reginfo nginxhelm

# Render a new service and make it active
./render nginxhelm/v1
git add .
git commit -m "enable nginxhelm/v1"
./push
```
