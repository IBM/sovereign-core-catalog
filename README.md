# IBM Sovereign Core public catalog

---

## Table of contents

1. [What is the IBM Sovereign Core public catalog?](#what-is-the-ibm-sovereign-core-public-catalog)
2. [The four integration levels](#the-four-integration-levels)
3. [The 5 pillars of sovereign attributes](#the-5-pillars-of-sovereign-attributes)
4. [Repository structure](#repository-structure)
5. [Asset lifecycle states](#asset-lifecycle-states)
6. [Contribution flow & lifecycle](#contribution-flow--lifecycle)

---

## What is the IBM Sovereign Core public catalog?

A governed, Git-backed public catalog powering the Sovereign Core platform catalog. Partner listings have historically lived in spreadsheets and wikis — stale, unvalidated, and with no way to verify sovereignty claims programmatically. The Sovereign Core Catalog solves this with a public Git repository on **github.com/IBM** where all catalog entries are structured YAML validated by CI on every PR. Partners contribute via pull request, IBM reviews and merges, and the repo feeds both the Public Catalog UI and the deployment engine, providing a governed onboarding path for partners and ISVs.

> **Design principle:** The repo stores only metadata, compliance pointers, and deployment references. No binaries, no secrets, no product code. All actual artifacts remain in vendor-owned OCI registries.

| Metric | Count |
|---|---|
| Component types | 4 |
| Partner companies | 7 |
| Catalog entries | 43 |
| JSON schemas | 6 |

Browse the public catalog at [www.ibm.com/products/sovereign-core/catalog](https://www.ibm.com/products/sovereign-core/catalog)

---

## The four integration levels

A product enters the catalog at one of four integration levels. The level describes the depth of platform integration, the evidence required, and the permitted seller claim.

### Level 1 — Validated

The minimum entry level. The product is discoverable in the catalog and confirmed to run on Sovereign Core. Installation and day-two operations remain the responsibility of the product team. Validation is performed either by the Sovereign Core SRE team or by the partner providing documented proof. The permitted seller claim is "Validated on Sovereign Core." This level is achievable in approximately five business days once intake inputs are complete. It is the right entry point for a product with an active customer opportunity that will deepen its platform integration over time.

### Level 2 — BYOP (Bring Your Own Product)

The product has been installed on a supported Sovereign Core configuration using a repeatable, tested procedure and is available via the BYOP mechanism in both the Central IT catalog and the Tenant Catalog. A runbook, version matrix, and upgrade approach are required. The permitted seller claim is "Catalog compatible on Sovereign Core." Target timeline is two to three weeks from the point where installation assets are ready.

### Level 3 — Integrated

The product is deployed from the catalog and connected to the platform services required for normal operation — identity, secrets, observability, metering, and lifecycle management — with tested recovery procedures in place. The permitted seller claim is "Integrated with Sovereign Core." This takes four to eight weeks depending on integration gaps and requires funded engineering effort from the owning team.

### Level 4 — Premium

Sovereign Core owns the end-to-end experience from provisioning through day-two operations, upgrade, rollback, and recovery. This is the standard to which watsonx is held as the first target product. The permitted seller claim is "Premium on Sovereign Core." Milestones are agreed at intake because this is a funded joint engineering commitment between the product team and Sovereign Core, requiring long-term commitment from both sides. Unified support is a defining characteristic of a Premium listing — it must be agreed and in place before go-live, not defined afterward.

> **Important:** The integration level is not the same as the sovereignty posture of the product, and the two should not be conflated. A Level 2 listing can have an excellent sovereignty profile — air-gapped, offline activation, customer-held keys — while a Level 4 product may still have external dependencies that need to be managed. Sovereignty posture is assessed separately, and it is what an auditor or regulated buyer will ask about.

---

## The 5 pillars of sovereign attributes

### Pillar 1 — Sovereignty & legal jurisdiction
- Corporate HQ & ultimate parent HQ
- Air-gap capability declaration
- External dependency endpoints (must be empty or redirectable)
- SBOM format & base image provenance

### Pillar 2 — Kubernetes architecture & day-2
- Delivery mechanism (Helm / Operator / Kustomize)
- Target Kubernetes & OCP versions
- CSI access modes & snapshot support
- Node selectors & resource guarantees

### Pillar 3 — Security & infrastructure isolation
- Pod Security Standard (`restricted` / `baseline` / `privileged`)
- Read-only root filesystem
- RBAC scope (namespace-isolated vs cluster-wide)
- FIPS 140-3 compliance
- KMS / HSM integration

### Pillar 4 — Compliance, auditing & certification
- Framework attestations (BSI-C5, SecNumCloud, FedRAMP, Gaia-X)
- Verifiable credentials from third-party auditors
- Structured audit log output (stdout/stderr JSON)
- OpenTelemetry / FluentBit SIEM mapping

### Pillar 5 — Ecosystem & commercial models
- Offline / disconnected licensing (BYOL or Marketplace-Metered)
- Offline licence validation mechanism
- Support personnel security clearance level
- Remote access prohibition declaration (no inbound VPN / reverse tunnel)

> All sovereignty claims are **self-declared by the vendor**. IBM does not independently audit or certify any claim. Customers are responsible for independent validation before deployment.

---

## Repository structure

Two-step model: company identity first, component listing second.

```
sovereign-core-catalog/
├── .github/workflows/            # CI validation — runs on every PR
├── companies/                    # WHO you are — one profile per organisation
│   └── <company-slug>/
│       └── profile.yaml          # Jurisdiction, certifications, contact
├── components/                   # WHAT you are listing
│   ├── software/                 # K8s operators, Helm charts, apps
│   │   └── <company>/<product>/
│   │       ├── <version>/
│   │       │   └── metadata.yaml
│   │       └── sovereigncore_ext/helm/
│   │           └── values-mapping.yaml   # One-click deploy overlay
│   ├── ai-models/                # Foundation models & weights
│   │   └── <company>/<model>/
│   │       └── metadata.yaml
│   ├── hardware/                 # GPUs, servers, storage, HSMs
│   │   └── <company>/<product>/
│   │       └── profile.yaml
│   └── services/                 # MSPs, hosting, SI, audit partners
│       └── <company>/
│           └── profile.yaml
├── schemas/                      # JSON Schema — one per resource kind
├── scripts/                      # Local validation before opening PR
└── docs/                         # Governance, onboarding, and briefing docs
```

> **The two-step rule:** Every partner must first submit a `companies/<slug>/profile.yaml` PR and have it merged before any component listing will pass CI validation. The `companyRef` field in every metadata file must resolve to an existing company profile.

---

## Asset lifecycle states

Every catalog entry carries a `lifecycleStatus` field that controls the Public Catalog visibility and deployment eligibility. Transitions are enforced by the CI pipeline — a PR cannot set `approved` directly without passing through `review` first.

```
                    ┌─────────────────────────────────────────────────────┐
                    │                                                     │
   Partner          │  CI pass +        IBM reviewer      Owner marks    │  Removed from
   submits PR       │  IBM queued       approves &        end-of-life    │  active feed;
       │            │  for review       merges PR              │         │  retained for
       ▼            │      │                │                  ▼         │  audit
   ┌───────┐        │  ┌────────┐      ┌──────────┐      ┌────────────┐  │  ┌─────────┐
   │ Draft │ ──────►│  │ Review │─────►│ Approved │─────►│ Deprecated │──┼─►│ Retired │
   └───────┘        │  └────────┘      └──────────┘      └────────────┘  │  └─────────┘
       ▲            │      │                                              │
       └────────────┼──────┘                                              │
     Review         │  Changes requested                                  │
     feedback       └─────────────────────────────────────────────────────┘
```

| State | Storefront | Deployable | Description |
|---|---|---|---|
| `draft` | Hidden | No | Entry submitted, CI validation pending |
| `review` | Hidden | No | CI passed, awaiting IBM reviewer approval |
| `approved` | Public | Yes | Merged to main, visible in the Public Catalog |
| `deprecated` | Visible with warning | Discouraged | End-of-life signalled, successor available |
| `retired` | Hidden | No | Removed from active catalog, retained for audit |

---

## Contribution flow & lifecycle

### Asset lifecycle states

```
Draft → Review → Approved → Deprecated → Retired
  │        │         │           │            │
Partner  CI pass  IBM merges  Owner flags  Removed from
submits  queued   PR          end-of-life  feed; retained
PR       for                              for audit
         review
```

### Three-stage partner contribution

**Stage 1 — Join: submit your company profile**
Fork repo → create `companies/<your-slug>/profile.yaml` → run `./scripts/validate-local.sh` → open PR titled `[Company Join] Your Company Name`. Must be merged before any component PR.

**Stage 2 — List: propose a component**
Create `components/<type>/<your-slug>/<product>/<version>/metadata.yaml` → validate locally → open PR titled `[New Listing] Software: Acme — ProductName v1.0`. CI validates schema automatically.

**Stage 3 — Maintain: keep your listing current**
New version? Add a new `<version>/` folder via PR. Deprecating? Update `lifecycleStatus: deprecated`. Withdrawing? Set `lifecycleStatus: retired`. All changes via PR — never direct push to main.

> **CI validation runs automatically on every PR** — schema correctness, required fields, taxonomy vocabulary, secrets scan, broken reference check. Human IBM review only after CI passes.
