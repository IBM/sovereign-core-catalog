# Sovereign Core Store

---

## Table of Contents

1. [What is the Sovereign Store?](#what-is-the-sovereign-store)
2. [The 5 Pillars of Sovereign Attributes](#the-5-pillars-of-sovereign-attributes)
3. [Repository Structure](#repository-structure)
4. [Asset Lifecycle States](#asset-lifecycle-states)
5. [Contribution Flow & Lifecycle](#contribution-flow--lifecycle)

---

## What is the Sovereign Store?

A governed, Git-backed catalog powering the Sovereign Core platform storefront. Partner listings have historically lived in spreadsheets and wikis — stale, unvalidated, and with no way to verify sovereignty claims programmatically. The Sovereign Store solves this with a public Git repository on **github.com/IBM** where all catalog entries are structured YAML validated by CI on every PR. Partners contribute via pull request, IBM reviews and merges, and the repo feeds both the storefront UI and the deployment engine, providing a governed onboarding path for partners and ISVs.

> **Design principle:** The repo stores only metadata, compliance pointers, and deployment references. No binaries, no secrets, no product code. All actual artifacts remain in vendor-owned OCI registries.

| Metric | Count |
|---|---|
| Component types | 4 |
| Partner companies | 7 |
| Catalog entries | 43 |
| JSON schemas | 6 |

---

## The 5 Pillars of Sovereign Attributes

Metadata fields are architectural constraints — not informational labels. CI rejects entries that fail any pillar.

### Pillar 1 — Sovereignty & Legal Jurisdiction
- Corporate HQ & ultimate parent HQ
- Air-gap capability declaration
- External dependency endpoints (must be empty or redirectable)
- SBOM format & base image provenance

### Pillar 2 — Kubernetes Architecture & Day-2
- Delivery mechanism (Helm / Operator / Kustomize)
- Operator maturity level (L1–L5)
- Target Kubernetes & OCP versions
- CSI access modes & snapshot support
- Node selectors & resource guarantees

### Pillar 3 — Security & Infrastructure Isolation
- Pod Security Standard (`restricted` / `baseline` / `privileged`)
- Read-only root filesystem
- RBAC scope (namespace-isolated vs cluster-wide)
- FIPS 140-3 compliance
- KMS / HSM integration

### Pillar 4 — Compliance, Auditing & Certification
- Framework attestations (BSI-C5, SecNumCloud, FedRAMP, Gaia-X)
- Verifiable credentials from third-party auditors
- Structured audit log output (stdout/stderr JSON)
- OpenTelemetry / FluentBit SIEM mapping

### Pillar 5 — Ecosystem & Commercial Models
- Offline / disconnected licensing (BYOL or Marketplace-Metered)
- Offline licence validation mechanism
- Support personnel security clearance level
- Remote access prohibition declaration (no inbound VPN / reverse tunnel)

> All sovereignty claims are **self-declared by the vendor**. IBM does not independently audit or certify any claim. Customers are responsible for independent validation before deployment.

---

## Repository Structure

Two-step model: company identity first, component listing second.

```
sovereign-store/
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

## Asset Lifecycle States

Every catalog entry carries a `lifecycleStatus` field that controls storefront visibility and deployment eligibility. Transitions are enforced by the CI pipeline — a PR cannot set `approved` directly without passing through `review` first.

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
| `approved` | Public | Yes | Merged to main, visible in storefront |
| `deprecated` | Visible with warning | Discouraged | End-of-life signalled, successor available |
| `retired` | Hidden | No | Removed from active catalog, retained for audit |

---

## Contribution Flow & Lifecycle

### Asset Lifecycle States

```
Draft → Review → Approved → Deprecated → Retired
  │        │         │           │            │
Partner  CI pass  IBM merges  Owner flags  Removed from
submits  queued   PR          end-of-life  feed; retained
PR       for                              for audit
         review
```

### Three-Stage Partner Contribution

**Stage 1 — Join: submit your Company Profile**
Fork repo → create `companies/<your-slug>/profile.yaml` → run `./scripts/validate-local.sh` → open PR titled `[Company Join] Your Company Name`. Must be merged before any component PR.

**Stage 2 — List: propose a component**
Create `components/<type>/<your-slug>/<product>/<version>/metadata.yaml` → validate locally → open PR titled `[New Listing] Software: Acme — ProductName v1.0`. CI validates schema automatically.

**Stage 3 — Maintain: keep your listing current**
New version? Add a new `<version>/` folder via PR. Deprecating? Update `lifecycleStatus: deprecated`. Withdrawing? Set `lifecycleStatus: retired`. All changes via PR — never direct push to main.

> **CI validation runs automatically on every PR** — schema correctness, required fields, taxonomy vocabulary, secrets scan, broken reference check. Human IBM review only after CI passes.

