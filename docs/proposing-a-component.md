# Proposing a component listing

This guide explains how a member company submits a new component — software, hardware, AI model, or service — to the IBM Sovereign Core public catalog. Each listing is merged via a **Pull Request reviewed by IBM maintainers**.

> **Prerequisite:** Your company must already have a merged Company Profile before submitting a component. If you have not joined yet, see [Joining the community](joining-the-community.md) first.

---

## Overview

A component listing is a structured YAML metadata file that describes a product's sovereignty posture, technical architecture, and deployment characteristics. It does **not** contain binaries — all actual artifacts (container images, Helm charts, model weights) remain in your own external registries. The listing is a pointer and a set of validated declarations.

There are four component categories:

| Category | Directory | Metadata file |
|---|---|---|
| Software (K8s / VM / bare-metal apps) | `components/software/<slug>/<product>/<version>/` | `metadata.yaml` |
| Hardware (servers, GPUs, accelerators) | `components/hardware/<slug>/<product>/` | `profile.yaml` |
| AI Models (foundation models, weights) | `components/ai-models/<slug>/<model>/` | `metadata.yaml` |
| Services (hosting, SI, audit, consulting) | `components/services/<slug>/` | `profile.yaml` |

---

## Step-by-step process

### 1. Choose the right category

Determine which category applies to your product:

- **Software** — Any application deployed on Kubernetes, a VM, or bare-metal. Includes databases, ingress controllers, monitoring stacks, security tools, etc.
- **Hardware** — Physical infrastructure components: GPU cards, servers, storage appliances, network hardware.
- **AI Models** — Foundation model weights or fine-tuned derivatives. The listing points to an external weights repository (e.g., OCI registry or HuggingFace).
- **Services** — Non-product offerings: managed hosting, system integration, security auditing, training, or MSP operations.

### 2. Fork and branch

Fork the repository (if you haven't already) and create a branch named:

```
add/<category>/<your-company-slug>/<product-slug>
```

For example: `add/software/company-abc/nginx-ingress`

### 3. Create the metadata file

Place your file at the path shown in the table above and fill in the required fields.

#### Minimum required fields (all categories)

Every metadata file must contain:

```yaml
apiVersion: sovereign-catalog.io/v1alpha1
kind: <SoftwareListing | HardwareProfile | ModelListing | ServiceProfile>
metadata:
  companyRef: "companies/<your-company-slug>"   # must point to your merged company profile
  vendor: "<Your Company Display Name>"
  product: "<Product Name>"
```

A `jurisdiction` or `sovereignty.corporateHQ` block is also required in every file. See the JSON Schemas under `schemas/` for the full per-category field requirements.

#### Software listings

Software listings additionally require:

- `spec.architecture.format` — deployment target: `Kubernetes`, `VM`, or `BareMetal`
- `spec.architecture.airgapReady` — `true` or `false`
- `spec.deployment.type` — delivery mechanism: `Helm`, `Operator`, `Kustomize`, etc.
- `spec.deployment.repository` — the OCI URI of your Helm chart or operator image (external registry — not hosted here)
- `spec.security.podSecurityStandard` — `baseline` or `restricted`

Version directories follow semantic versioning: `components/software/<slug>/<product>/v<MAJOR.MINOR.PATCH>/metadata.yaml`

#### Sovereign Core extension (software only, optional)

If your software supports one-click deployment via IBM Sovereign Core, you may include a deployment-acceleration overlay alongside your listing:

```
components/software/<slug>/<product>/sovereigncore_ext/helm/values-mapping.yaml
```

This file is a `SovereignCoreHelmMapping` that maps platform-provided values into your Helm chart's value schema. It is optional at listing time and can be added in a follow-up PR. The detailed specification for this extension format is **TBD** and will be published in a future revision of this guide.

### 4. Validate locally

```bash
./scripts/validate-local.sh
```

This runs a structural smoke test across all YAML files in `components/` and `companies/`. Fix any reported errors before opening a PR.

### 5. Open a pull request

Open a PR from your branch against `main`. Use the title format:

```
[New Listing] <Category>: <Your Company Name> — <Product Name>
```

For example: `[New Listing] Software: Company ABC — Nginx Sovereign Ingress v3.0.0`

Your PR should contain only the files for the single component being submitted. Do not bundle multiple unrelated product listings in one PR.

### 6. Review by IBM

IBM maintainers review all component PRs. The review process covers:

| Check | Who performs it |
|---|---|
| Schema validation (required fields, types, enum values) | Automated CI (GitHub Actions) |
| Correctness of `companyRef` (points to a merged company profile) | Automated CI |
| Accuracy of jurisdiction and sovereignty declarations | IBM reviewer |
| Completeness of sovereignty pillar fields (airgap, SBOM, FIPS, RBAC, etc.) | IBM reviewer |
| Plausibility of certification claims | IBM reviewer (self-declared; not independently verified) |

The IBM reviewer may request changes via PR comments. Address all requested changes on the same branch before the PR is merged.

---

## Self-declaration notice

All fields in a component listing — including certification claims, airgap readiness, FIPS compliance, and supply-chain attestations — are **self-declared by the submitting company**. IBM does not independently audit or verify these claims. Customers are responsible for validating all declarations before making deployment decisions. See the [Customer guide](customer-guide.md) for details on how to approach independent validation.

---

## After your listing is merged

| Action | Next step |
|---|---|
| Publish a new product version | Open a new PR adding the new `<version>/metadata.yaml` under the same product directory |
| Update an existing listing | See [Managing your listing — Updating](managing-your-listing.md#updating-a-listing) |
| Remove a product from the catalog | See [Managing your listing — Removing a component](managing-your-listing.md#removing-a-component) |
| Add a Sovereign Core extension | Open a follow-up PR adding `sovereigncore_ext/helm/values-mapping.yaml` |
