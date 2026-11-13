# MongoDB Enterprise Advanced VM for IBM Z / LinuxONE (s390x)

Helm chart and catalog entry for running **MongoDB Enterprise Advanced** as an OpenShift Virtualization (OCP Virt) VirtualMachine on **IBM Z and LinuxONE (`linux/s390x`)** nodes, deployed by the **Sovereign Core BYOP broker**.

> **Deployment model.** This chart is deployed exclusively by the Sovereign Core BYOP broker. Instances are provisioned, updated and deleted through the Sovereign Core catalog — do not install, upgrade or uninstall the chart directly with Helm. The only Helm commands used with this chart are the packaging and push steps in [Publishing the chart](#publishing-the-chart).

| | |
|---|---|
| Chart name | `mongodb-vm` |
| Chart version | `1.1.34` (`chart/Chart.yaml` → `version`) |
| App version | `8.0` (`chart/Chart.yaml` → `appVersion`) |
| Container image | `quay.io/mongodb-ea-bootc/mongodb-ea-bootc-containerdisk:8.0-s390x` |
| Workload | OCP Virt `VirtualMachine`, CDI `DataVolume`, `Secret`, `Service`, `NetworkPolicy`, `ServiceAccount` |

VirtualMachines are pinned to s390x nodes (`nodeSelector: kubernetes.io/arch: s390x`) with machine type `s390-ccw-virtio`, boot disk is provisioned on a `ReadWriteOnce` Block PersistentVolumeClaim via CDI, and supports standalone VM as well as 3-member Replica Set HA with VIP primary failover. For chart values and broker integration details, see [`chart/README.md`](chart/README.md).

---

## Contents of this folder

```
mongodb-s390x/
├── README.md                  # this file
├── catalog/                   # Sovereign Core catalog definition
│   ├── catalog.yaml           #   display name, description, category, tags
│   ├── metadata.yaml          #   import metadata (sourceType, sourceRepo, sourceVersion, images)
│   ├── schema.json            #   provisioning parameters (JSON Schema)
│   └── metrics.json           #   metrics definition (currently empty)
├── chart/                     # Helm chart source + packaged chart
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── README.md              #   chart-level documentation
│   ├── templates/
│   └── mongodb-vm-1.1.36.tgz  # packaged chart (output of `helm package`)
├── template/
│   └── values.yaml.tmpl       # values template rendered by the Sovereign Core broker
└── v8.0/
    └── metadata.yaml          # SoftwareListing for catalog validation
```

> The `.tgz` in `chart/` is generated from the chart source next to it. After any chart change, regenerate and re-push it (see [Repackaging after a chart change](#repackaging-after-a-chart-change)).

---

## Cluster Prerequisites & Spoke Preparation

Before importing the spoke cluster into the Sovereign Core control plane, ensure the target OpenShift s390x cluster has the required operators installed for any optional features you intend to enable:

| Feature | Chart Value / Schema Parameter | Cluster Prerequisite | Notes |
|---|---|---|---|
| **VM Workloads & Storage** | Core / mandatory | OpenShift Virtualization (KubeVirt), CDI, and Ceph RBD Block StorageClass | Base prerequisite for deploying s390x VMs. |
| **Backup & Snapshot Schedules** | `backup.enabled: true` | **Red Hat OADP (Velero)** operator installed on spoke cluster | **Install OADP on the spoke cluster BEFORE importing the cluster into Sovereign Core.** Cluster import applies control-plane pull secret and ITMS/IDMS mirror policies; installing OADP first ensures operator bundle images from `registry.redhat.io` pull cleanly. |
| **MetalLB VIP LoadBalancer** | `vip.enabled: true`<br>`vip.lb_type: "external"` | MetalLB Operator configured with `IPAddressPool` | Provides LoadBalancer VIP routing. KubeVirt `tcpSocket: 27017` probe ensures all members report Ready for clean ArgoCD sync, while MongoDB client drivers discover the replica set topology and route writes to Primary. |
| **External Service Blocking** | `network.blockExternalServices: true` | **Kyverno** policy engine installed on spoke cluster | **Mutual Exclusivity:** Kyverno policy enforces `ClusterIP`-only services (`mdb-net-03`). If `network.blockExternalServices: true` is enabled, `vip.enabled` must be `false` (or `vip.lb_type` set to internal `ClusterIP`). If using MetalLB external VIP (`vip.enabled: true`), keep `network.blockExternalServices: false` (default). |
| **Prometheus Alerting** | `monitoring.enabled: true` | OpenShift Monitoring / User Workload Monitoring | Evaluates replica set member health and VM pod readiness rules (`mdb-rs-01`). The namespace label hook automatically applies `openshift.io/user-monitoring: "true"`. |

### Required Container Images for Spoke Mirroring

For air-gapped spoke clusters, mirror the following images into your internal Quay registry under `sovcloud/`:

| Image Source | Purpose |
|---|---|
| `registry.redhat.io/openshift4/ose-cli:latest` | Hook jobs: namespace labeling (`mdb-gov-01`) and Concert SSH keygen (`mdb-con-01`) |
| `registry.redhat.io/openshift-logging/fluentd-rhel9:latest` | Audit log shipper DaemonSet (`mdb-aud-05`) |
| `quay.io/mongodb-ea-bootc/mongodb-ea-bootc-containerdisk:8.0-s390x` *(or `8.3.2.44-s390x`)* | RHEL 9 Image Mode bootable QCOW2 containerdisk for KubeVirt CDI |

---

## Provisioning via the Sovereign Core catalog

The listing in `catalog/` defines the `MongoDB Enterprise Advanced VM s390x` service. Provisioning parameters are defined in [`catalog/schema.json`](catalog/schema.json):

| Parameter | Required | Notes |
|---|---|---|
| `clusterTarget` | yes | ArgoCD cluster name to deploy to |
| `namespace` | yes | Target namespace, default `mongodb-s390x` |
| `instanceName` | yes | Unique instance name prefix |
| `diskImage.sourceContainerDisk` | yes | ContainerDisk image reference in registry |
| `mongodb.databaseName` | yes | Initial database name |
| `mongodb.databaseUser` | yes | Initial database username |
| `ha.enabled` | yes | Enable 3-member Replica Set High Availability (default `false`) |
| `ha.replicaCount` | no | Number of replica set members (default `3`) |
| `vip.enabled` | no | Enable primary-only VIP routing (default `false`) |
| `vip.lb_type` | no | VIP service type: `local` (NodePort) or `external` (MetalLB LoadBalancer) |
| `vip.metallbAddressPool` | no | MetalLB IPAddressPool name (required when `vip.lb_type: external`) |
| `network.blockExternalServices` | no | Enable Kyverno policy blocking NodePort/LoadBalancer (default `false`, requires Kyverno) |
| `compliance.enableEncryption` | no | Enable WiredTiger encryption-at-rest (default `false`) |
| `compliance.auditLog.enabled` | no | Enable JSON audit logging in mongod.conf (default `false`) |
| `logging.rsyslog.enabled` | no | Enable rsyslog drop-in configuration in VM guest (default `false`) |
| `logging.fluentbit.enabled` | no | Deploy Fluent-bit DaemonSet for log collection and shipping (default `false`) |
| `backup.enabled` | no | Enable Velero Schedule for VM snapshot backup (default `false`, requires OADP) |
| `monitoring.enabled` | no | Enable PrometheusRule alerting for Replica Set health (default `false`) |

`template/values.yaml.tmpl` maps these parameters to chart values when the broker deploys the chart. Broker behaviour to be aware of:

- Credentials are auto-generated on the spoke cluster and stored in a Kubernetes `Secret` (`<instance>-mongodb-creds`) — they are never written to chart values or Git.
- The boot disk image is pulled from the internal registry / ContainerDisk mirror via CDI.
- Dedicated ServiceAccount RBAC and default-deny NetworkPolicies are rendered to satisfy compliance controls.

---

## Publishing the chart

You need **Helm 3.8 or later** (for `helm push` / `helm registry login`) and credentials for the Sovereign Core Quay registry (or your chosen OCI registry).

The packaged chart is at `chart/mongodb-vm-1.1.34.tgz`; its name and version derive from `chart/Chart.yaml`. Replace every `<placeholder>` with your own values. **Never commit real credentials** — pass them via environment variables or a secret store.

```bash
export REGISTRY=<quay-host>              # e.g. the Quay host of your Sovereign Core deployment
export NAMESPACE=<org>/<path>            # target repository path in Quay
export QUAY_USERNAME=<username>
export QUAY_PASSWORD=<password-or-robot-token>

# 1. Log in (password via stdin keeps it out of shell history)
echo "$QUAY_PASSWORD" | helm registry login "$REGISTRY" \
  --username "$QUAY_USERNAME" --password-stdin

# 2. Push — Helm appends the chart name, result: oci://$REGISTRY/$NAMESPACE/mongodb-vm:1.1.34
helm push chart/mongodb-vm-1.1.34.tgz "oci://$REGISTRY/$NAMESPACE"

# 3. Verify
helm show chart "oci://$REGISTRY/$NAMESPACE/mongodb-vm" --version 1.1.34
```

If the registry uses a self-signed certificate, prefer `--ca-file` (run `helm push --help` for the TLS flags in your Helm version).

The repository's `scripts/import.sh` pushes charts to `oci://<QUAY_REGISTRY>/sovcloud/cp/sovereign-cloud-platform/byop/charts`. Use that path as `NAMESPACE` to land your manual push in the same location the import pipeline uses; confirm with your Sovereign Core administrator.

---

## Repackaging after a chart change

1. Edit the chart under `chart/` (templates, `values.yaml`, ...).
2. **Bump `version`** in `chart/Chart.yaml` (and `appVersion` if the MongoDB version changes). A registry will not accept a different chart under an existing version.
3. Lint and render:
   ```bash
   helm lint chart
   helm template test chart --set diskImage.sourceContainerDisk=quay.io/example/disk:latest > /dev/null
   ```
4. Rebuild the package from this folder (`mongodb-s390x/`):
   ```bash
   rm -f chart/mongodb-vm-*.tgz
   helm package chart --destination chart
   ```
5. Verify: `helm show chart chart/mongodb-vm-<new-version>.tgz`.
6. Keep these in sync with the new version:
   - `catalog/metadata.yaml` → `sourceVersion`
   - `catalog/metadata.yaml` / `v8.0/metadata.yaml` → image tag / `version` if the MongoDB version changed
   - `template/values.yaml.tmpl` → `diskImage` / version if changed
7. Push the new `.tgz` (see [Publishing the chart](#publishing-the-chart)).

---

## Notes

- `catalog/metadata.yaml` sets `sourceRepo: oci://quay.io/mongodbhelm/mongodb-vm` and `sourceVersion: "1.1.34"`. `scripts/import.sh` pulls the chart from there, so push the chart to that location (or update `sourceRepo`) before importing the listing.
- `helm lint` reports one informational message (`icon is recommended`) because `Chart.yaml` has no `icon`; it is not an error.
