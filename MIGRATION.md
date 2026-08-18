# Migrating from v2.x to v3.0.0

v3.0.0 tightens the **default** trust-policy sub scope from org-wide (`repo:ORG@ID/*` —
any repo, branch, or event) to per-repo: only workflows on the repo's default branch.

- **`default_branch` is a new required field** on every `github_repos` entry (e.g.
  `"main"`) — plans fail with a type error until it is added.
- **Pull-request-triggered runs are rejected by default.** Pipelines that plan on PRs
  (including the GlueOps OpenTofu CD action's PR plans) must set
  `allow_pull_requests = true` per repo, or their PR workflows fail closed at
  AssumeRoleWithWebIdentity.
- Repos deploying from other branches, from tags, or via environment-gated jobs also
  fail closed under the new default — set `allowed_subs` for those repos before bumping.
- `allowed_subs` and the ID-claim enforcement are unchanged; repos that set
  `allowed_subs` are unaffected by all of the above.
- With `immutable_subs_only = false`, legacy-format equivalents of the default patterns
  are included (also branch-scoped — no longer org-wide). The variable is now
  **deprecated** (native OpenTofu variable deprecation — setting it emits a warning):
  opt your repos into immutable subject claims instead; it will be removed in a future
  major version.
- **The minimum OpenTofu version is now 1.11** (required by the native deprecation
  attribute), and the module is OpenTofu-only — Terraform does not support it. Bump any
  CI pins (e.g. an `OPENTOFU_VERSION` variable) to >= 1.11 before adopting v3.

# Migrating from v1.x to v2.0.0

v2.0.0 defaults trust policies to **immutable-only** sub patterns and replaces the
v1.1.0 `include_legacy_sub_pattern` variable (removed) with `immutable_subs_only`
(default `true`, inverted meaning).

- If every configured repo mints immutable subject claims — created after 2026-07-15 or
  opted in via the `use_immutable_subject` OIDC setting — no changes are needed. Applying
  updates each role's trust policy in place, dropping the legacy `repo:ORG/*` pattern.
- If some repos still mint legacy-format tokens, set `immutable_subs_only = false` to keep
  the legacy pattern until they are opted in. **Do not skip this**: with the default, a
  non-opted repo's tokens stop matching the sub condition and its deploys fail closed.
- If you set `include_legacy_sub_pattern` in v1.1.0, replace it: `true` becomes
  `immutable_subs_only = false`, and `false` becomes the default (remove the argument).

Repos that set `allowed_subs` are unaffected.

# Migrating from v0.x to v1.0.0

v1.0.0 changes how trust policies identify GitHub repositories: instead of matching the
mutable `org/repo` name in the token's `sub` claim, roles now pin the **immutable numeric
GitHub IDs** (`repository_owner_id`, `repository_id`) with exact-match conditions.

## Why

GitHub enforces **immutable subject claims** for repositories created, renamed, or
transferred after **2026-07-15**: their tokens carry
`sub = repo:ORG@ORG_ID/REPO@REPO_ID:...` instead of `repo:ORG/REPO:...`. The v0 trust
policy (`StringLike sub = "repo:ORG/REPO:*"`) can never match that format, so new or
renamed repos silently fail `AssumeRoleWithWebIdentity`. Name-based matching is also
vulnerable to name recycling (org/repo names can be re-registered by someone else;
numeric IDs cannot).

The numeric ID claims are present in **every** GitHub.com Actions token — old or new sub
format, any trigger type — and cannot be removed by any sub-claim customization. A missing
claim fails closed in IAM.

## What you must change

Each entry in `github_repos` needs two new required fields:

```hcl
github_repos = {
  "demo-app" = {
    github_org     = "example-org"
    github_org_id  = "1234567"   # NEW — numeric owner ID
    repo_id        = "9876543"   # NEW — numeric repository ID
    policy_arns    = []
    state_account  = "state"
    infra_accounts = { core = "OrganizationAccountAccessRole" }
  }
}
```

Look the IDs up per repo:

```sh
gh api repos/ORG/REPO --jq '"repo_id: \(.id)  org_id: \(.owner.id)"'
```

Pitfalls:

- Use the **REST numeric ids** shown above. GraphQL node IDs (e.g. `R_kgDOG...`) will not
  match and are rejected by input validation.
- `gh api` silently follows rename/transfer redirects — eyeball `.full_name` in the
  response to confirm you queried the repo you think you did.
- `.owner.id` is correct for user-owned repos too (the claim is the owner's ID, org or user).
- The repository's Settings → Actions OIDC page previews the exact `sub` your tokens carry.

## What happens at apply

- In-place `UpdateAssumeRolePolicy` on each role: no role recreation, ARNs unchanged,
  running workflows and already-issued STS credentials unaffected. Zero downtime.
- Repos already minting immutable-format tokens (created/renamed after 2026-07-15) are
  broken under v0 and **start working** as soon as the new policy propagates.
- Repos that previously had managed policies attached (`policy_arns` non-empty) gain an
  inline `AssumeRoles` policy granting access to their own S3 state role — in v0 that
  access silently disappeared when any managed policy was attached.
- Rollback: repin the previous ref and re-apply; trust policies revert in place.

## Behavior changes to be aware of

- **Rename-proof**: repo and org renames no longer break authentication (the IDs don't
  change). The default `sub` patterns are org-name-based, so after an org rename update
  `github_org` at your convenience — until then the sub match fails closed.
- **Transfers fail closed**: transferring a repo to a different owner changes the token's
  `repository_owner_id`, so the role stops being assumable until you update
  `github_org_id` (and `github_org`). This is intentional.
- **Reusable workflows**: tokens carry the **calling** repository's IDs, same as v0's
  name-based matching.
- **Sub scoping**: by default the trust policy matches any workflow in the repo (the sub
  condition exists because IAM requires one for the GitHub provider and covers both the
  legacy and immutable formats org-wide; enforcement is the ID conditions). To scope a
  repo to a branch or environment, set `allowed_subs`, e.g.:

  ```hcl
  allowed_subs = ["repo:example-org@1234567/demo-app@9876543:ref:refs/heads/main"]
  ```

  Use the immutable format shown above if the repo has been opted into immutable subject
  claims (or was created after 2026-07-15), and the legacy `repo:example-org/demo-app:...`
  format otherwise.

## Scope caveats

- GitHub.com only. GHES and GHEC data-residency (`ghe.com`) tenants use a different OIDC
  issuer and are not supported by this module.
- The `repository_id` / `repository_owner_id` condition keys are supported by AWS in
  commercial partitions; GovCloud/China support is not documented by AWS at the time of
  writing (roles there would fail closed).
