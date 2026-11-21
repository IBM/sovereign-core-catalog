# Quay Deployment Scripts

## Scripts

| Script | Role |
|---|---|
| `deploy-quay.sh` | Orchestrator — checks dependencies, runs phases 1–2, and prints the registry endpoint |
| `1-install-operator.sh` | Install the Quay Operator via OLM and wait for the operator deployment |
| `2-deploy-registry.sh` | Apply the QuayRegistry CR and wait for Quay to become available |
| `show-quay-outputs.sh` | Print `QUAY_REGISTRY` — run any time after deployment |

## Dependency checks

| Check | `deploy-quay.sh` | `1-install-operator.sh` | `2-deploy-registry.sh` |
|---|:---:|:---:|:---:|
| **`oc`** | ✓ | ✓ | ✓ |
| **Cluster connectivity** | ✓ | ✓ | ✓ |

> Sub-scripts keep their own checks so they can be run standalone.
> When invoked via `deploy-quay.sh`, all checks have already passed.
