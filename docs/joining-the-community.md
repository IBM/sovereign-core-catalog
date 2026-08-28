# Joining the IBM Sovereign Core public catalog community

This guide explains how a company becomes a recognized member of the IBM Sovereign Core public catalog. Membership is the prerequisite for any component listing. It is established by merging a **Company Profile** pull request into this repository.

---

## Overview

The IBM Sovereign Core catalog uses a **GitOps model**: your company's identity, jurisdiction, and certifications live as a versioned YAML file under `companies/<company-slug>/profile.yaml`. Once that file is merged, your `company-slug` becomes the canonical reference used in every component you later submit.

Community membership:

- Establishes your company as a trusted namespace in the catalog.
- Creates the `companyRef` anchor that all of your component listings must point to.
- Does **not** automatically list any products — component listings are submitted separately (see [Proposing a component](proposing-a-component.md)).

---

## Step-by-step process

### 1. Fork the repository

Fork `sovereign-core-catalog` to your organisation's GitHub account and create a branch named after your company:

```
add/company/<your-company-slug>
```

A **slug** is a lowercase, hyphen-separated identifier with no spaces or special characters (e.g., `company-abc`, `acme-corp-eu`). Choose one and use it consistently — it cannot be changed after merge without opening a rename PR.

### 2. Create your company profile

Create the file at:

```
companies/<your-company-slug>/profile.yaml
```

Use the template below. Fields marked `# required` must be present; fields marked `# optional` may be omitted if not applicable.

```yaml
apiVersion: sovereign-catalog.io/v1alpha1
kind: CompanyProfile
metadata:
  slug: "<your-company-slug>"                   # required — must match the directory name
  displayName: "<Legal entity name>"             # required
spec:
  jurisdiction:
    corporateHQ: "<Country/Region>"              # required — e.g. "France/EU", "Germany/EU", "USA"
    ultimateParentCompanyHQ: "<Country/Region>"  # required — set same as corporateHQ if independent
    registrationNumber: "<National reg. number>" # optional but strongly recommended
  contact:
    website: "https://<your-website>"            # required
    partnerEmail: "<email for catalog matters>"  # required
  certifications:                                # optional — list active or in-progress frameworks
    - framework: "<e.g. ISO-27001>"
      status: "<Active | In Progress | Planned>"
    - framework: "<e.g. SecNumCloud>"
      status: "<Active | In Progress | Planned>"
```

**Jurisdiction guidance:**

| Field | What to put |
|---|---|
| `corporateHQ` | The country and region of the legal entity submitting this profile. |
| `ultimateParentCompanyHQ` | The country and region of the ultimate parent company (the topmost owner in the corporate tree). If your company is independent, repeat `corporateHQ`. |

This information is not cosmetic — downstream catalog consumers use it to filter suppliers that fall under foreign extraterritorial laws (e.g., the US CLOUD Act, UK IPA).

### 3. Validate locally

Run the structural smoke test before opening a PR:

```bash
./scripts/validate-local.sh
```

The script checks that your file contains the required `apiVersion`, `kind`, and jurisdiction fields. Fix any failures before proceeding.

### 4. Open a pull request

Open a PR from your branch against `main`. Use the title format:

```
[Company Join] <Your Company Display Name>
```

Your PR must contain **only** the new `companies/<slug>/profile.yaml` file. Do not bundle component listings in the same PR — they are reviewed separately.

### 5. Review and merge

IBM maintainers review the PR for:

- Correct schema structure (automated CI check runs first).
- Accuracy and completeness of the `jurisdiction` block.
- Validity of any certification claims (self-declared at this stage; customers validate independently).

Once approved and merged, your company is a member of the community and your `company-slug` is live in the catalog.

---

## What happens after you join

| Action | Next step |
|---|---|
| List a software, hardware, AI model, or service | See [Proposing a component](proposing-a-component.md) |
| Update your profile (new cert, address change, etc.) | See [Managing your listing](managing-your-listing.md) |
| Leave the community | See [Managing your listing — Opting out](managing-your-listing.md#opting-out) |

---

## Important notes

- **Self-declaration:** Certification claims in your profile are self-declared. The catalog does not independently verify them. Customers are expected to validate all claims before making procurement decisions (see the [Customer guide](customer-guide.md)).
- **One profile per legal entity:** Each distinct legal entity (e.g., a regional subsidiary with its own sovereignty posture) should have its own `company-slug` and profile.
- **Profile ownership:** The company that opens the join PR is recorded as the owner. Only PRs from accounts recognised as maintainers of that company's namespace will be approved for future changes to that profile.
