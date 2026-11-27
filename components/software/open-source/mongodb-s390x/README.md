# MongoDB Enterprise Advanced VM for IBM Z / LinuxONE (s390x)

Catalog entry for running **MongoDB Enterprise Advanced** as an OpenShift Virtualization (OCP Virt) VirtualMachine on **IBM Z and LinuxONE (`linux/s390x`)** nodes, deployed by the **Sovereign Core BYOP broker**.

> **Deployment model.** The Helm chart is **not stored in this repository**. It is developed and published from `SovereignCore/scripts/mongodb-vm-s390x-tech-preview/chart` and referenced here only through `sourceRepo` / `sourceVersion` in `catalog/metadata.yaml`. Instances are provisioned, updated and deleted through the Sovereign Core catalog — do not install, upgrade or uninstall the chart directly with Helm.

| | |
|---|---|
| Chart name | `mongodb-vm` |
| Chart reference | `oci://quay.io/mongodbhelm/mongodb-vm` — **placeholder**, set to your own registry (`catalog/metadata.yaml` → `sourceRepo`) |
| Chart version | `1.1.46` (`catalog/metadata.yaml` → `sourceVersion`) |
| App version | `8.0` |
| Container image | `quay.io/mongodb-ea-bootc/mongodb-ea-bootc-containerdisk:8.0-s390x` — **placeholder** for the boot-disk image that you build and publish to your preferred registry (`catalog/metadata.yaml` → `images[].source`) |
| Workload | OCP Virt `VirtualMachine`, CDI `DataVolume`, `Secret`, `Service`, `NetworkPolicy`, `ServiceAccount` |

VirtualMachines are pinned to s390x nodes (`nodeSelector: kubernetes.io/arch: s390x`) with machine type `s390-ccw-virtio`, boot disk is provisioned on a `ReadWriteOnce` Block PersistentVolumeClaim via CDI, and supports standalone VM as well as 3-member Replica Set HA with VIP primary failover. For chart values and development details, see the chart's own README in `SovereignCore/scripts/mongodb-vm-s390x-tech-preview/chart/README.md`.

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
├── template/
│   └── values.yaml.tmpl       # values template rendered by the Sovereign Core broker
└── v8.0/
    └── metadata.yaml          # SoftwareListing for catalog validation
```

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

The spoke cluster is air-gapped once it is imported, so every image it needs must be mirrored into your internal Quay registry under `sovcloud/` first.

The MongoDB boot-disk image below is a **placeholder**: it stands for the bootc containerdisk image that you build and push to your own registry location. Replace `source` in `catalog/metadata.yaml` with that location and use the latest published image version.

Mirror the following images:

| Image Source | Purpose |
|---|---|
| `registry.redhat.io/openshift4/ose-cli:latest` | Hook jobs: namespace labeling (`mdb-gov-01`) and Concert SSH keygen (`mdb-con-01`) |
| `registry.redhat.io/openshift-logging/fluentd-rhel9:latest` | Audit log shipper DaemonSet (`mdb-aud-05`) |
| `registry.redhat.io/ansible-automation-platform/ee-minimal-rhel9:2.18.9-3` | Compliance checks CronJob (SSH runner that writes the evidence ConfigMap) |
| `quay.io/mongodb-ea-bootc/mongodb-ea-bootc-containerdisk:8.0-s390x` *(or `8.3.2.44-s390x`)* | **Placeholder** for the image you push to your own registry location: RHEL 9 Image Mode bootable QCOW2 containerdisk for KubeVirt CDI (use the latest published version) |

---

## Provisioning via the Sovereign Core catalog

The listing in `catalog/` defines the `MongoDB Enterprise Advanced VM s390x` service. Provisioning parameters are defined in [`catalog/schema.json`](catalog/schema.json):

| Parameter | Required | Notes |
|---|---|---|
| `clusterTarget` | yes | ArgoCD cluster name to deploy to |
| `namespace` | no | Not a user input. The namespace is the tenant ID (`tenantId`, falling back to the account ID) |
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

## Updating to a new chart version

The chart is built from `SovereignCore/scripts/mongodb-vm-s390x-tech-preview/chart` (bump `version` in its `Chart.yaml`, `helm package`) and pushed with `helm push` to the OCI registry of your choice. The `oci://quay.io/mongodbhelm/mongodb-vm` value in this catalog is only a placeholder; set `sourceRepo` to wherever you publish the chart. Once the new version is available in the registry, update this folder:

- `catalog/metadata.yaml` → `sourceVersion`
- `catalog/catalog.yaml` → `spec.version` (set to the version of the chart you pushed)
- `v8.0/metadata.yaml` → `spec.catalog.sourceVersion` (and image tag / `version` if the MongoDB version changed)
- `template/values.yaml.tmpl` → `diskImage` / version if changed

---

## Notes

- `catalog/metadata.yaml` sets `sourceRepo: oci://quay.io/mongodbhelm/mongodb-vm` (placeholder) and `sourceVersion: "1.1.46"`. `scripts/import.sh` pulls the chart from `sourceRepo`, so before importing the listing, publish the chart to your registry and update `sourceRepo` (and `sourceVersion`) in `catalog/metadata.yaml` and `v8.0/metadata.yaml`, and set `spec.version` in `catalog/catalog.yaml` to the same chart version.
