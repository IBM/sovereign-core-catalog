# PostgreSQL s390x Helm Chart

This Helm chart deploys a PostgreSQL instance on IBM Z and LinuxONE (**s390x**) nodes using the official [`s390x/postgres`](https://hub.docker.com/r/s390x/postgres) Docker image.

The chart is designed to integrate with the Sovereign Core catalog broker (`byop-broker`) and follows the same conventions as other charts in this repository (MariaDB, etcd, etc.).

---

## Key differences from the standard `postgres` catalog entry

| Feature | `postgres` (x86) | `postgres-s390x` |
|---|---|---|
| Image | Bitnami `oci://registry-1.docker.io/bitnamicharts/postgresql` | Official `s390x/postgres:17.11` |
| Architecture | `linux/amd64` | `linux/s390x` |
| Node scheduling | No restriction | `nodeSelector: kubernetes.io/arch: s390x` |
| Deployment type | Bitnami chart (external) | Custom Helm chart (this repo) |
| Pull secret | Not required | Required on Docker Hub rate-limited clusters |
| OpenShift SCC | Standard | `anyuid` required (initContainer runs as root) |

---

## Prerequisites

- Helm 3.x
- Kubernetes 1.24+ or OpenShift 4.10+ with **s390x** worker nodes
- A `ReadWriteOnce`-capable StorageClass (e.g. `ocs-storagecluster-ceph-rbd`)
- On Docker Hub rate-limited clusters: a Docker Hub account with a Personal Access Token (PAT)

> **OpenShift only:** Grant `anyuid` SCC to the namespace's default ServiceAccount so the
> `fix-permissions` initContainer can run as root:
> ```bash
> oc adm policy add-scc-to-user anyuid -z default -n <your-namespace>
> ```

---

## Configuration reference

| Parameter | Description | Default |
|---|---|---|
| `image.registry` | Optional registry prefix (e.g. internal mirror) | `""` |
| `image.repository` | Container image repository | `s390x/postgres` |
| `image.tag` | PostgreSQL image tag | `17.11` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `imagePullSecrets` | List of pre-existing pull secret names | `[]` |
| `dockerhubPullSecret.create` | Let the chart create a Docker Hub pull secret | `false` |
| `dockerhubPullSecret.secretName` | Name for the chart-created pull secret | `dockerhub-pull-secret` |
| `dockerhubPullSecret.dockerServer` | Registry server for the pull secret | `docker.io` |
| `dockerhubPullSecret.dockerUsername` | Docker Hub username | `""` |
| `dockerhubPullSecret.dockerPassword` | Docker Hub PAT | `""` |
| `dockerhubPullSecret.dockerEmail` | Email for the pull secret | `""` |
| `auth.superuserPassword` | PostgreSQL superuser (`postgres`) password | `change-me-superuser-password` |
| `auth.database` | Application database name | `appdb` |
| `auth.username` | Application database user | `appuser` |
| `auth.password` | Application user password | `change-me-password` |
| `persistence.enabled` | Enable PVC for data volume | `true` |
| `persistence.size` | PVC storage size | `1Gi` |
| `persistence.storageClass` | StorageClass name for PVC | `""` |
| `statefulset.replicas` | Number of replicas | `1` |
| `pgConfig` | Extra PostgreSQL config key/value pairs | `{}` |
| `instance.name` | Broker instance name (used in resource naming) | `""` |
| `instance.environment` | Deployment environment label | `""` |

---

## Image pull secret — how it works

Docker Hub enforces anonymous pull rate limits. On clusters that cannot pull
`docker.io/s390x/postgres:17.11` without authentication, you must provide
credentials. The chart has **two independent mechanisms** for this.

### Mechanism 1 — Chart creates the secret (`dockerhubPullSecret.create=true`)

The chart renders a `kubernetes.io/dockerconfigjson` Secret directly into the
namespace and automatically adds its name to `pod.spec.imagePullSecrets`.

```
values.yaml
  dockerhubPullSecret.create: true
  dockerhubPullSecret.secretName: "dockerhub-pull-secret"
  dockerhubPullSecret.dockerUsername: "<your-username>"
  dockerhubPullSecret.dockerPassword: "<your-PAT>"
          │
          ▼
templates/dockerhub-pull-secret.yaml
  → Secret "dockerhub-pull-secret" created in namespace
    type: kubernetes.io/dockerconfigjson
          │
          ▼
templates/statefulset.yaml
  → pod.spec.imagePullSecrets: [{name: "dockerhub-pull-secret"}]
          │
          ▼
kubelet → decodes .dockerconfigjson → authenticates to docker.io → pulls image
```

**Dependency:** Non-empty `dockerUsername` + `dockerPassword`. If `create: false`
(the default), the template renders empty — no Secret is created and nothing is
added to `imagePullSecrets`.

### Mechanism 2 — Reference a pre-existing secret (`imagePullSecrets`)

The chart does **not** create any Secret. It only puts the supplied name(s) into
`pod.spec.imagePullSecrets`. The Secret must already exist in the namespace before
`helm install` runs.

```
values.yaml
  imagePullSecrets:
    - dockerhub-pull-secret          ← name reference only, no creation
          │
          ▼
templates/statefulset.yaml
  → pod.spec.imagePullSecrets: [{name: "dockerhub-pull-secret"}]
          │
          ▼
kubelet → looks up Secret in namespace → if missing: ErrImagePull immediately
```

**Dependency:** Secret must be pre-created externally before pod start.

### How both mechanisms combine

`statefulset.yaml` merges both sources into a single list:

```
$pullSecrets  =  imagePullSecrets[]           (explicit pre-existing names)
              +  dockerhubPullSecret.secretName  (if create=true)
```

Both can be active simultaneously — for example, one corporate registry secret
(pre-existing) plus one Docker Hub secret (chart-created).

---

## Installing in a development environment

### Step 1 — Create the namespace

```bash
# Kubernetes
kubectl create namespace postgres-s390x-dev

# OpenShift
oc new-project postgres-s390x-dev
```

**OpenShift only** — grant `anyuid` SCC so the initContainer can fix volume
permissions:

```bash
oc adm policy add-scc-to-user anyuid -z default -n postgres-s390x-dev
```

### Step 2 — Choose your pull secret approach

#### Option A — Let the chart create the Docker Hub secret (simplest)

Pass credentials directly via `--set`. The chart creates the Secret and wires
it into `imagePullSecrets` automatically. Nothing needs to exist beforehand.

```bash
helm install pg-dev ./chart \
  --namespace postgres-s390x-dev \
  --set instance.name=dev \
  --set instance.environment=dev \
  --set auth.superuserPassword="SuperSecure123!" \
  --set auth.password="AppSecure456!" \
  --set auth.database=devdb \
  --set auth.username=devuser \
  --set persistence.size=5Gi \
  --set persistence.storageClass=ocs-storagecluster-ceph-rbd \
  --set dockerhubPullSecret.create=true \
  --set dockerhubPullSecret.dockerUsername=<your-dockerhub-username> \
  --set dockerhubPullSecret.dockerPassword=<your-dockerhub-PAT>
```

> **Note:** The Docker Hub PAT will be stored in the Helm release history
> (`helm get values pg-dev`). Acceptable for dev; avoid in production.

#### Option B — Pre-create the secret yourself (recommended for shared clusters)

```bash
# 1. Create the secret (once per namespace, not stored in Helm history)
kubectl create secret docker-registry dockerhub-pull-secret \
  --docker-server=docker.io \
  --docker-username=<your-dockerhub-username> \
  --docker-password=<your-dockerhub-PAT> \
  --namespace postgres-s390x-dev

# OpenShift: link to the default SA so all pods in the namespace use it
oc secrets link default dockerhub-pull-secret \
  --for=pull -n postgres-s390x-dev

# 2. Install referencing the secret by name
helm install pg-dev ./chart \
  --namespace postgres-s390x-dev \
  --set instance.name=dev \
  --set instance.environment=dev \
  --set auth.superuserPassword="SuperSecure123!" \
  --set auth.password="AppSecure456!" \
  --set auth.database=devdb \
  --set auth.username=devuser \
  --set persistence.size=5Gi \
  --set persistence.storageClass=ocs-storagecluster-ceph-rbd \
  --set "imagePullSecrets[0]=dockerhub-pull-secret"
```

### Step 3 — Verify the deployment

```bash
# Watch the pod start (initContainer runs first, then main container)
kubectl get pods -n postgres-s390x-dev -w
# or: oc get pods -n postgres-s390x-dev -w

# Confirm pod is on an s390x node
kubectl get pod pg-dev-postgres-s390x-dev-0 -n postgres-s390x-dev \
  -o jsonpath="{.spec.nodeName}" | xargs -I{} \
  kubectl get node {} -o jsonpath="{.status.nodeInfo.architecture}"
# Expected output: s390x

# Check all resources
kubectl get statefulset,service,secret,configmap,pvc \
  -n postgres-s390x-dev

# Tail logs
kubectl logs -f postgres-s390x-dev-0 -n postgres-s390x-dev
```

### Step 4 — Run a SQL smoke test

```bash
kubectl exec -it postgres-s390x-dev-0 -n postgres-s390x-dev -- \
  psql -U devuser -d devdb -c "SELECT version();"

kubectl exec -it postgres-s390x-dev-0 -n postgres-s390x-dev -- \
  psql -U devuser -d devdb -c "
    CREATE TABLE IF NOT EXISTS smoke_test (
      id  serial PRIMARY KEY,
      msg text,
      ts  timestamptz DEFAULT now()
    );
    INSERT INTO smoke_test(msg) VALUES ('hello from s390x');
    SELECT * FROM smoke_test;
  "
```

### Step 5 — Uninstall

```bash
helm uninstall pg-dev -n postgres-s390x-dev
kubectl delete namespace postgres-s390x-dev
# or: oc delete project postgres-s390x-dev
```

---

## Helm install vs catalog broker install — behaviour comparison

The chart supports two deployment modes. The pull secret behaviour differs
between them by design.

### Direct Helm install

You supply all values directly. The chart can either create the Docker Hub
Secret itself (`dockerhubPullSecret.create=true`) or reference a pre-existing
one (`imagePullSecrets`). Credentials may appear in Helm release history.

### Catalog broker install (byop-broker)

The broker renders `template/values.yaml.tmpl` into a Helm values override
file stored in a GitOps repository, then runs `helm install`. Key differences:

- `dockerhubPullSecret.create` is **hardcoded to `false`** in the broker
  template — credentials are never written to the values file or Git.
- The pull secret name is passed as a **provisioning parameter**
  (`image_pull_secret_name` in `catalog/schema.json`). The user supplies the
  name of a pre-existing Secret at provision time via the catalog UI.
- The image repository is rewritten to the platform's internal mirror
  (`BYOP_REGISTRY/byop/postgres-s390x`) — Docker Hub is not called at all
  in a fully air-gapped broker deployment.

```
Broker flow:
  User provisions instance
    → supplies image_pull_secret_name = "dockerhub-pull-secret"
    → broker renders values.yaml.tmpl
         imagePullSecrets:
           - name: dockerhub-pull-secret   ← name only, no credentials
         image.repository: BYOP_REGISTRY/byop/postgres-s390x
    → helm install with rendered values
    → pod references pre-existing Secret in namespace
```

**Pre-requisite for broker deployments:** The platform admin must pre-create
the pull secret in the target namespace before any instance is provisioned.
The broker has no mechanism to create it — that is intentional (security
boundary).

### Side-by-side comparison

| | Option A: chart creates secret | Option B: pre-existing secret | Catalog broker |
|---|---|---|---|
| Who creates the Secret | The chart | You (manually) | Platform admin |
| Credentials in Helm values | Yes — `--set dockerPassword=...` | No | Never |
| Credentials in Git/GitOps | No | No | Never (hardcoded `create: false`) |
| Image source | `docker.io/s390x/postgres:17.11` | `docker.io/s390x/postgres:17.11` | `BYOP_REGISTRY/byop/postgres-s390x` |
| `imagePullSecrets` populated by | Chart appends secret name automatically | Explicit list in values | `spec.image_pull_secret_name` provisioning param |
| If Secret is missing | Secret created fresh | `ErrImagePull` | `ErrImagePull` |
| PAT visible in `helm get values` | Yes | No | No |
| Best for | Dev / quick testing | CI/CD, shared clusters | Production sovereign deployments |

---

## Node scheduling

`statefulset.yaml` enforces:

```yaml
nodeSelector:
  kubernetes.io/arch: s390x
```

This guarantees the pod lands on an IBM Z / LinuxONE node in a heterogeneous
cluster. On a pure s390x cluster (like `ocpz-standard-5`) all nodes satisfy
this selector automatically.

## OpenShift volume permissions

The official `s390x/postgres` image expects to own its data directory as
uid/gid 999 (`postgres`). OpenShift assigns a random UID from the namespace
UID range, which causes `initdb` to fail with a permission error.

The chart handles this with:

1. **`securityContext.fsGroup: 999`** — OpenShift chowns the mounted volume to
   GID 999 before containers start.
2. **`initContainer: fix-permissions`** — runs as `runAsUser: 0` and executes
   `chown -R 999:999 /var/lib/postgresql/data` to guarantee ownership.

Both require `anyuid` SCC on the namespace's default ServiceAccount (see
Prerequisites above).

## Probes

Both `readinessProbe` and `livenessProbe` use `pg_isready`, which is bundled
in the official PostgreSQL image. It checks the database is accepting
connections without requiring password authentication.

## Made with Bob
