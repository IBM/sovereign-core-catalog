# Managing your listing

This guide covers all post-merge lifecycle actions for a company already participating in the IBM Sovereign Core public catalog: updating an existing component listing, publishing a new product version, removing a component, updating your company profile, and opting out of the community entirely.

All changes follow the same **GitOps / Pull Request model** as the original submission.

---

## Updating a listing

Use this process to correct a field, add a newly obtained certification, update a registry URI, or change any other attribute of an existing component or company profile.

### For a component listing

1. Fork the repository (if you haven't already) and create a branch named:

   ```
   update/<category>/<your-company-slug>/<product-slug>
   ```

2. Edit the relevant `metadata.yaml` or `profile.yaml` in-place.

3. Run the local validation script:

   ```bash
   ./scripts/validate-local.sh
   ```

4. Open a PR against `main` with the title format:

   ```
   [Update Listing] <Category>: <Your Company Name> — <Product Name>
   ```

5. IBM maintainers review and merge the change.

### For your company profile

Follow the same steps above but target `companies/<your-company-slug>/profile.yaml` and use the branch name:

```
update/company/<your-company-slug>
```

---

## Publishing a new product version

Software listings are versioned by directory. To add a new release of an existing product, add a new version directory — **do not overwrite the previous version's directory**.

1. Create the new directory:

   ```
   components/software/<slug>/<product>/v<NEW_VERSION>/
   ```

2. Copy the previous version's `metadata.yaml` as a starting point and update the `version` field and any changed attributes.

3. Validate and open a PR:

   ```
   [New Version] Software: <Your Company Name> — <Product Name> v<NEW_VERSION>
   ```

Old version directories remain in the catalog until you explicitly request their removal (see below). Customers running older deployments may rely on them.

---

## Removing a component

To withdraw a product from the catalog — for example, because it has reached end-of-life, a security issue makes it unsuitable for sovereign use, or your company no longer supports it — open a deletion PR.

1. Create a branch named:

   ```
   remove/<category>/<your-company-slug>/<product-slug>
   ```

2. **Do not simply delete the directory.** Instead, add a `WITHDRAWN.md` file at the top of the product directory (e.g., `components/software/<slug>/<product>/WITHDRAWN.md`) with the following content:

   ```markdown
   # Withdrawn

   **Date:** YYYY-MM-DD
   **Reason:** <Brief public reason — e.g., "End of life", "Superseded by <product>", "Security advisory">
   **Contact:** <email for customers with questions>
   ```

   This preserves a public audit trail for customers who may have deployed the component.

3. Open a PR with the title:

   ```
   [Withdraw Component] <Category>: <Your Company Name> — <Product Name>
   ```

4. IBM maintainers review and merge.

> **Note on hard deletion:** If there is a legal or security reason requiring the metadata file itself to be removed from the repository history, contact the IBM maintainer team directly via `partnerEmail` on your company profile. Hard deletions require explicit maintainer approval.

---

## Opting out

Opting out removes your company from the community entirely — your company profile and all associated component listings are withdrawn.

### Process

1. Create a branch named:

   ```
   opt-out/company/<your-company-slug>
   ```

2. Add a `WITHDRAWN.md` to each of your component directories (see [Removing a component](#removing-a-component) above for the format).

3. Add a `WITHDRAWN.md` at the top level of your company profile directory:

   ```
   companies/<your-company-slug>/WITHDRAWN.md
   ```

   With content:

   ```markdown
   # Company opted out

   **Date:** YYYY-MM-DD
   **Reason:** <Optional — may be left blank>
   **Contact:** <forwarding contact if customers have questions>
   ```

4. Open a single PR covering all the above files:

   ```
   [Opt Out] Company: <Your Company Display Name>
   ```

5. IBM maintainers review and merge.

### What opt-out means

- Your company profile and all product listings are marked withdrawn. The `WITHDRAWN.md` files serve as a permanent, auditable record.
- New submissions under your `company-slug` are not accepted unless you re-join by opening a new join PR in the future.
- Customers who have already deployed your software are not affected by the catalog change — the catalog holds only metadata pointers, not binaries.

---

## Transferring ownership

If your company is acquired, rebranded, or the team responsible for catalog maintenance changes, open a PR to:

1. Update `companies/<slug>/profile.yaml` with the new `displayName`, `corporateHQ`, `ultimateParentCompanyHQ`, and `partnerEmail`.
2. Add a comment in the PR explaining the change (acquisition, rebranding, internal team change, etc.).

For slug renames (rare — only when the legal entity itself changes materially), contact the IBM maintainer team directly. A slug rename requires a coordinated migration of all `companyRef` values across existing listings.

---

## Summary of PR title conventions

| Action | Branch name | PR title prefix |
|---|---|---|
| Update a component | `update/<cat>/<slug>/<product>` | `[Update Listing]` |
| Update company profile | `update/company/<slug>` | `[Update Profile]` |
| New product version | `add/software/<slug>/<product>` | `[New Version]` |
| Withdraw a component | `remove/<cat>/<slug>/<product>` | `[Withdraw Component]` |
| Opt out entirely | `opt-out/company/<slug>` | `[Opt Out]` |
