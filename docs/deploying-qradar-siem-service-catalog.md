# Deploying IBM QRadar SIEM via the Sovereign Core Service Catalog

This guide walks end users through provisioning and managing an **IBM QRadar SIEM** instance using the **Sovereign Core Service Catalog** (GitOps CSB Broker Web Interface).

---

## 1. Overview

The Sovereign Core Service Catalog allows self-service deployment of enterprise services onto OpenShift clusters using GitOps.

**IBM QRadar SIEM 7.5.0** is deployed on **OpenShift Virtualization** via Helm charts. Depending on your workload requirements, you can choose between two deployment topologies:

- **Standalone Plans (`Tiny`, `Small`, `Medium`, `Large`)**: Deploys a single console Virtual Machine (VM) with DHCP networking. Suitable for development, proof-of-concept, test, or standard monitoring tiers.
- **High Availability (HA) Plans (`Small HA`, `Medium HA`, `Large HA`)**: Deploys a primary + secondary VM pair connected with a fixed `10.0.0.x` private synchronization network for automatic failover. Suitable for mission-critical and production environments.

---

## 2. Prerequisites

Before you begin, ensure you have:
1. URL and credentials to access the **Service Catalog** web interface (e.g., `https://byop-catalog-app-byop.apps.<cluster-domain>/`).
2. Deployment target details (Cluster name/identifier).
3. Network information:
   - Primary and secondary DNS server IP addresses.
   - Desired timezone (e.g., `UTC`, `America/New_York`, `Europe/London`).
4. Credentials for the QRadar instance:
   - Secure password for the QRadar Web Console `admin` user.
   - Secure password for the underlying OS `root` user.

---

## 3. Step-by-Step Deployment Guide

### Step 1: Open the Service Catalog

1. Open your browser and navigate to the Service Catalog web portal.
2. In the top navigation, locate the **Available Services** section.

---

### Step 2: Choose Your Service Plan

1. Locate the **QRadar SIEM (Helm)** card:

   ```
   +-------------------------------------------------------------------------------+
   | QRadar SIEM (Helm)                                                            |
   |                                                                               |
   | QRadar SIEM 7.5.0 on OpenShift Virtualization via Helm chart. Supports        |
   | single-node console deployments and two-node HA pairs. Standalone plans       |
   | deploy a single console VM with DHCP networking. HA plans deploy a primary +   |
   | secondary VM with fixed 10.0.0.x private networking. Requires plan,           |
   | instance name, DNS server, and QRadar credentials only.                       |
   |                                                                               |
   | Available Plans:                                                              |
   | [ Tiny ]      [ Small ]      [ Medium ]      [ Large ]                        |
   | [ Small HA ]  [ Medium HA ]  [ Large HA ]                                     |
   +-------------------------------------------------------------------------------+
   ```

2. Select the plan that matches your capacity, resilience, and hardware budget:

| Plan Category | Plan ID | Display Name | Topology | VM Count | vCPU (per VM) | Memory (per VM) | Root Disk (per VM) | Total Cluster Resources | Target Environment / Notes |
|---|---|---|---|---|---|---|---|---|---|
| **Standalone** | `tiny` | **Tiny** | Standalone | 1 Console VM | **8 vCPU** | **32 GB RAM** | **250 GB** | 8 vCPU / 32 GB RAM / 250 GB Disk | Dev / test / evaluation only |
| **Standalone** | `small` | **Small** | Standalone | 1 Console VM | **16 vCPU** | **64 GB RAM** | **250 GB** | 16 vCPU / 64 GB RAM / 250 GB Disk | Functional testing / QA |
| **Standalone** | `medium` | **Medium** | Standalone | 1 Console VM | **24 vCPU** | **96 GB RAM** | **250 GB** | 24 vCPU / 96 GB RAM / 250 GB Disk | Staging / mid-tier ingestion |
| **Standalone** | `large` | **Large** | Standalone | 1 Console VM | **48 vCPU** | **192 GB RAM** | **500 GB** | 48 vCPU / 192 GB RAM / 500 GB Disk | High-throughput standalone |
| **High Availability** | `small-ha` | **Small HA** | High Availability | 2 VMs (Primary + Secondary) | **16 vCPU** | **64 GB RAM** | **250 GB** | **32 vCPU / 128 GB RAM / 500 GB Disk** | ✅ Minimum validated plan for HA (production) |
| **High Availability** | `medium-ha` | **Medium HA** | High Availability | 2 VMs (Primary + Secondary) | **24 vCPU** | **96 GB RAM** | **250 GB** | **48 vCPU / 192 GB RAM / 500 GB Disk** | Standard enterprise production |
| **High Availability** | `large-ha` | **Large HA** | High Availability | 2 VMs (Primary + Secondary) | **48 vCPU** | **192 GB RAM** | **500 GB** | **96 vCPU / 384 GB RAM / 1000 GB Disk** | High-capacity enterprise production |

> [!IMPORTANT]
> **HA Sizing Baseline:** The minimum recommended and validated plan for High Availability is **`Small HA`** (`16 vCPU / 64 GB RAM` per VM). Smaller footprints do not have sufficient memory headroom for DRBD replication and data synchronization between the primary and secondary nodes under load.
>
> In addition to the root disk, each virtual machine automatically mounts an installation media DataVolume (`30 GB`) backed by the cluster storage class (`ocs-storagecluster-ceph-rbd`).

3. Click on your chosen plan button (e.g., **Small HA** or **Tiny**). The **Provision Service** modal will appear.

---

### Step 3: Fill Out Provisioning Parameters

In the **Provision Service** dialog, fill in the required fields:

```
+-------------------------------------------------------------------------------+
| Provision Service                                                             |
| Create a new service instance from the selected plan.                         |
|                                                                               |
| Instance ID                                                                   |
| [ my-qradar-instance-01                                                     ] |
|                                                                               |
| Target Cluster                                                                |
| [ in-cluster (Hub)                                                          v]|
|                                                                               |
| Parameters (JSON)                                            [ Fill Example ] |
| +---------------------------------------------------------------------------+ |
| | {                                                                         | |
| |   "qradar": {                                                             | |
| |     "admin_password": "SecureAdm1nP@ssw0rd!",                             | |
| |     "dns_primary": "8.8.8.8",                                             | |
| |     "dns_secondary": "8.8.4.4",                                           | |
| |     "root_password": "VerySecureR00tP@ssw0rd!",                           | |
| |     "security_template": "Enterprise",                                    | |
| |     "timezone": "UTC"                                                     | |
| |   }                                                                       | |
| | }                                                                         | |
| +---------------------------------------------------------------------------+ |
|                                                                               |
|                                                     [ Cancel ]  [ Provision ]|
+-------------------------------------------------------------------------------+
```

1. **Instance ID**:
   - Enter a unique name for your deployment (e.g., `secops-qradar-prod` or `qateam-standalone-test4`).
   - Use lowercase alphanumeric characters and hyphens (`-`).

2. **Target Cluster**:
   - Select the target cluster from the dropdown (e.g., `in-cluster (Hub)`).

3. **Parameters (JSON)**:
   - Click the **Fill Example** button to automatically populate the JSON schema.
   - Update the values with your environment-specific settings:

```json
{
  "qradar": {
    "admin_password": "<YOUR_STRONG_ADMIN_PASSWORD>",
    "dns_primary": "<PRIMARY_DNS_IP>",
    "dns_secondary": "<SECONDARY_DNS_IP>",
    "root_password": "<YOUR_STRONG_ROOT_PASSWORD>",
    "security_template": "Enterprise",
    "timezone": "UTC"
  }
}
```

#### Parameter Reference

| Parameter | Type | Required | Description | Example |
|---|---|---|---|---|
| `qradar.admin_password` | String | **Yes** | Web console password for user `admin`. Use a strong password containing upper/lowercase, numbers, and symbols. | `"SecureAdm1nP@ssw0rd!"` |
| `qradar.root_password` | String | **Yes** | Operating system `root` password for the underlying virtual machine console. | `"VerySecureR00tP@ssw0rd!"` |
| `qradar.dns_primary` | String | **Yes** | IP address of the primary DNS resolver reachable by the VM. | `"8.8.8.8"` or `"10.x.x.x"` |
| `qradar.dns_secondary` | String | Optional | IP address of the secondary DNS resolver. | `"8.8.4.4"` or `"10.x.x.y"` |
| `qradar.security_template`| String | **Yes** | Security template profile for QRadar. Default is `"Enterprise"`. | `"Enterprise"` |
| `qradar.timezone` | String | **Yes** | Standard timezone identifier for log event timestamps. | `"UTC"`, `"EST"`, `"America/New_York"` |

---

### Step 4: Provision the Service

1. Double-check your entered configuration and passwords.
2. Click the blue **Provision** button.
3. The catalog broker triggers the GitOps workflow to spin up the VM(s) on OpenShift Virtualization.

---

### Step 5: Monitor Deployment in "Provisioned Instances"

1. Scroll down to the **Provisioned Instances** section on the main dashboard.
2. Locate your instance card by its **Instance ID**:

```
+-------------------------------------------------------------------------------+
| secops-qradar-prod                                              [ SUCCEEDED ] |
| Service: qradar      Plan: small-ha       Cluster: https://kubernetes.default.svc
| Created: 9/21/2026, 12:30:00 PM           Updated: 9/21/2026, 12:45:00 PM     |
|                                                                               |
| [ Delete ]  [ Check Status ]                                                  |
+-------------------------------------------------------------------------------+
```

3. **Status Indicators**:
   - **`IN_PROGRESS` / `PROVISIONING`**: The VM disks are being imported/cloned and boot-stage scripts are running.
   - **`SUCCEEDED`**: The QRadar deployment is fully configured and online.
4. **Action Buttons**:
   - **Check Status**: Click to inspect current runtime status, allocated IP address, and connection logs.
   - **Delete**: Deprovisions the VM(s) and cleans up storage volumes when the instance is no longer needed.

---

## 4. Accessing Your QRadar Instance

Once the status transitions to **`SUCCEEDED`**:

1. Click **Check Status** to obtain the assigned IP address or OpenShift Route/Service endpoint.
2. Open your web browser and navigate to:
   ```
   https://<QRADAR_IP_OR_HOSTNAME>/
   ```
3. Accept the SSL certificate prompt (if using a self-signed or internal CA certificate).
4. Log in with:
   - **Username**: `admin`
   - **Password**: The `admin_password` configured during Step 3.

---

## 5. Summary & Tips

- **Standalone vs HA**: Use standalone plans (`Tiny`, `Small`, `Medium`, `Large`) when rapid provisioning or minimal footprint is required. Use HA plans (`Small HA`, `Medium HA`, `Large HA`) for production instances requiring redundancy and zero single point of failure.
- **Save Credentials**: Keep a secure record of the `admin_password` and `root_password` configured during provisioning, as they are not retrievable in plain text from the UI later.
- **DNS Connectivity**: Ensure the specified DNS IPs are reachable from the OpenShift Virtualization node network so the QRadar instance can resolve required local directory or mail servers.
