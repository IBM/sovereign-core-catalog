# ArgoCD Spokes Scripts

## Scripts

| Script | Role |
|---|---|
| `add-spoke.sh` | Validate contexts, list current registrations, register a spoke cluster with the hub ArgoCD instance |
| `broker-add-spoke.sh` | Add a spoke cluster entry to the broker `values-generated.yaml` and redeploy |
| `broker-remove-spoke.sh` | Remove a spoke cluster entry from the broker `values-generated.yaml` and redeploy |

## Dependency checks

| Check | `add-spoke.sh` | `broker-add-spoke.sh` | `broker-remove-spoke.sh` |
|---|:---:|:---:|:---:|
| **`oc`** | ✓ | ✓ | ✓ |
| **`helm`** | | ✓ | ✓ |
| **`python3`** | | ✓ | ✓ |
| **Cluster connectivity (hub)** | ✓ | ✓ | ✓ |
| **Cluster connectivity (spoke)** | ✓ | ✓ | |
| **`--hub-context` arg** | ✓ | | |
| **`--spoke-context` arg** | ✓ | ✓ | |
| **`--spoke-name` arg** | | | ✓ |
| **`--source` arg** | | ✓ | ✓ |
| **Hub context in kubeconfig** | ✓ | | |
| **Spoke context in kubeconfig** | ✓ | ✓ | |
| **ArgoCD namespace on hub** | ✓ | | |
| **`values-generated.yaml` exists** | | ✓ | ✓ |

> Each script checks its own dependencies so it can be run standalone.
