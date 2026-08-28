# Customer guide: Using the IBM Sovereign Core public catalog

This guide is for **Sovereign Core customers** and operators evaluating or deploying sovereign cloud infrastructure. It explains how to browse the public catalog, interpret what you find, validate provider claims independently, and — when you are ready to deploy — obtain artifacts and enable Sovereign Core deployment extensions.

---

## Understanding the public catalog

The IBM sovereign core catalog is a **metadata registry**, not a software distribution channel.

| The catalog **does** contain | The catalog **does not** contain |
|---|---|
| Company profiles with jurisdiction and contact information | Actual container images, binaries, or model weights |
| Product listings with sovereignty posture declarations | Deployment keys, licenses, or support credentials |
| Technical architecture metadata (airgap readiness, FIPS status, RBAC scope, etc.) | Independently audited or IBM-verified compliance proofs |
| Pointers to external OCI registries where artifacts are hosted | Runtime access to any vendor's registry |

**All fields in every listing are self-declared by the submitting company.** IBM reviews submissions for schema correctness and plausibility, but does **not** independently audit or certify any claim. The responsibility for validating a provider's declarations before deployment rests with you.

---

## Step 1: Browse the catalog

The catalog is organised by component category. Start by browsing the directory that matches what you need:

| Category | Directory | What you find |
|---|---|---|
| Software | `components/software/` | Kubernetes apps, operators, databases, security tools, etc. |
| Hardware | `components/hardware/` | Servers, GPUs, storage, and network hardware |
| AI Models | `components/ai-models/` | Foundation model listings with hardware requirements |
| Services | `components/services/` | Hosting providers, system integrators, MSPs, auditors |

Each company directory under a category is namespaced by the company's `slug`. Within it, you will find one `profile.yaml` (hardware, services) or one directory per product (software, AI models), with versioned subdirectories for software.

**Key files to read for each candidate:**

1. `companies/<slug>/profile.yaml` — the company's jurisdiction, ultimate parent ownership, and certifications.
2. The component `metadata.yaml` or `profile.yaml` — the product's sovereignty posture, architecture, and deployment pointer.

---

## Step 2: Evaluate sovereignty claims

When reviewing a component, pay particular attention to the following fields. These are the attributes most relevant to a sovereign deployment:

### Jurisdiction

```yaml
jurisdiction:
  corporateHQ: "France/EU"
  ultimateParentCompanyHQ: "France/EU"
```

**Why it matters:** If the ultimate parent company is headquartered in a country with extraterritorial reach over data (e.g., the United States under the CLOUD Act, or the United Kingdom under the IPA), that company may be legally compelled to produce your data regardless of where it is physically stored. Review both fields, not just `corporateHQ`.

### Airgap readiness

```yaml
architecture:
  airgapReady: true
  dependencyEndpoints: []
```

**Why it matters:** A non-empty `dependencyEndpoints` list means the software attempts to contact external addresses at runtime. In a fully isolated sovereign environment, those connections will silently fail or require firewall exceptions. Confirm whether the vendor's declared endpoints can be mirrored to local equivalents.

### FIPS compliance

```yaml
security:
  fipsCompliant: true
```

**Why it matters:** FIPS 140-3 validated cryptographic modules may be required by your regulatory framework. This is self-declared — verify it against the vendor's FIPS certificates before deployment (see [Independent validation](#step-3-validate-claims-independently)).

### RBAC and security posture

```yaml
security:
  podSecurityStandard: "restricted"
  requiresClusterAdmin: false
  readOnlyRootFilesystem: true
```

**Why it matters:** Software that requests `Cluster-Wide` RBAC or `requiresClusterAdmin: true` poses a significant risk in multi-tenant sovereign clusters. Prefer components that declare `Namespace-Isolated` scope.

### Certifications

```yaml
certifications:
  - framework: "SecNumCloud"
    status: "Active"
  - framework: "BSI-C5"
    status: "Active"
```

**Why it matters:** These are self-declared. `Active` does not mean independently verified by this catalog. You must contact the issuing body or the vendor directly to confirm a certificate is current and in scope (see below).

---

## Step 3: Validate claims independently

The catalog is your starting point for discovery, **not** your final assurance gate. Before deploying any component in a production sovereign environment:

### Verify certifications

- Contact the certification body directly (e.g., ANSSI for SecNumCloud, BSI for C5, FedRAMP PMO for FedRAMP) and confirm the certificate is active and covers the specific product version you intend to deploy.
- Request a copy of the certification letter or audit report from the vendor.

### Verify jurisdiction and ownership

- Cross-reference `corporateHQ` and `ultimateParentCompanyHQ` against public company registries (e.g., national business registries, Companies House, SEC EDGAR).
- If the ultimate parent jurisdiction is a concern, ask the vendor for a legal opinion or data processing agreement that mitigates extraterritorial risk.

### Verify SBOM and supply chain

- Request the vendor's Software Bill of Materials (SBOM) in CycloneDX or SPDX format. This lets you audit which upstream dependencies and base images are included.
- Run your own vulnerability scan against the SBOM before deployment.

### Verify airgap behaviour

- Ask the vendor for a complete, documented list of external network calls the software makes during installation, operation, and upgrade.
- Conduct a network egress test in a sandboxed environment before production deployment.

### Verify support posture

- Confirm that support personnel clearance matches your environment's requirements.
- Confirm that the vendor's support model does not require inbound remote access (VPN or reverse tunnel) that would violate your sovereign perimeter.

---

## Step 4: Contact the provider

Once you have identified a component that appears suitable, contact the vendor directly using the `partnerEmail` in their company profile:

```
companies/<slug>/profile.yaml → spec.contact.partnerEmail
```

When reaching out, request:

- Access to container images and Helm charts from their external OCI registry (the registry URI is in the component's `deployment.repository` field).
- License keys or entitlement tokens if required.
- Their SBOM, FIPS certificates, and any audit reports relevant to your regulatory framework.
- Their support statement for your sovereign environment (including airgap and disconnected-billing procedures).
- Their data processing agreement and any jurisdiction-specific legal documentation.

The catalog facilitates discovery. Commercial, legal, and operational arrangements are made directly between you and the provider.

---

## Step 5: Deploying with Sovereign Core

> **Note:** The detailed Sovereign Core deployment workflow is **TBD** and will be documented in a future revision of this guide. The information below describes the current model at a high level.

### Sovereign Core extensions

Some software listings include a **Sovereign Core Extension** — a deployment-acceleration overlay that maps Sovereign Core platform values directly into the vendor's Helm chart. If a `sovereigncore_ext/` directory exists alongside a software listing, the product has been prepared for one-click deployment on Sovereign Core.

```
components/software/<slug>/<product>/sovereigncore_ext/helm/values-mapping.yaml
```

This file is a `SovereignCoreHelmMapping` that tells the Sovereign Core deployment engine how to translate platform-level configuration (node pools, TLS secrets, ingress classes, KMS references) into the chart's specific Helm values schema.

### Bringing artifacts into Sovereign Core

For software with a Sovereign Core extension, the general workflow is:

1. Obtain the vendor's artifacts (container images, Helm chart) from their external OCI registry, using the `deployment.repository` URI in the metadata.
2. Copy those artifacts into your Sovereign Core's internal registry (air-gap mirror).
3. Apply the `SovereignCoreHelmMapping` overlay to deploy the software using platform-native values.

The specifics of the artifact mirroring process and deployment engine API are **TBD** and will be covered in the Sovereign Core platform documentation when available.

---

## Quick reference

| Task | Where to look |
|---|---|
| Find a software product | `components/software/` |
| Find a hardware component | `components/hardware/` |
| Find a hosting or SI partner | `components/services/` |
| Find an AI model | `components/ai-models/` |
| Get a vendor's contact email | `companies/<slug>/profile.yaml` → `spec.contact.partnerEmail` |
| Check a vendor's jurisdiction | `companies/<slug>/profile.yaml` → `spec.jurisdiction` |
| Check a product's airgap status | Component `metadata.yaml` → `spec.architecture.airgapReady` |
| Check a product's security posture | Component `metadata.yaml` → `spec.security` |
| Find the OCI registry for a product | Component `metadata.yaml` → `spec.deployment.repository` |
| Check for a Sovereign Core extension | `components/software/<slug>/<product>/sovereigncore_ext/` |
