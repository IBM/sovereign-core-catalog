# MariaDB Helm Chart

This Helm chart deploys a simple MariaDB sample pod.

## Installation

```bash
helm install mariadb ./services/mariadb-helm/latest
```

## Configuration

The following table lists the configurable parameters of the MariaDB chart and their default values.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `pod.name` | Name of the pod | `mariadb-sample-pod` |
| `pod.labels.app` | App label for the pod | `mariadb` |
| `container.name` | Name of the container | `sample` |
| `container.image.repository` | Container image repository | `quay.io/libpod/alpine` |
| `container.image.tag` | Container image tag | `latest` |
| `container.image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `container.command` | Container command | `["/bin/sh", "-c", "sleep 3600"]` |
| `container.resources` | Container resource requests/limits | `{}` |
| `commonLabels` | Additional labels to apply to all resources | `{}` |
| `commonAnnotations` | Additional annotations to apply to all resources | `{}` |

## Example Custom Values

```yaml
pod:
  name: my-mariadb-pod
  labels:
    app: mariadb
    environment: production

container:
  image:
    tag: "3.18"
  resources:
    limits:
      cpu: 200m
      memory: 256Mi
    requests:
      cpu: 100m
      memory: 128Mi

commonLabels:
  team: database
  project: catalogathon
```

## Uninstallation

```bash
helm uninstall mariadb