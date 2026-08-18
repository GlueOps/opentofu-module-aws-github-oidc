# Adding a repo

The end-to-end path for giving a GitHub repo keyless AWS access via this module.

## 1. Look up the repo's numeric ID

```sh
gh api repos/ORG/REPO --jq '"repo_id: \(.id)  full_name: \(.full_name)"'
```

Use the REST numeric `id` — GraphQL node IDs (`R_kgDO...`) will not match and are rejected
by validation. `gh api` silently follows rename/transfer redirects, so eyeball `full_name`
to confirm you queried the repo you meant.

## 2. Add the entry

In the config that calls this module, append to `github_repos`:

```hcl
{
  repo_name      = "my-new-repo"
  repo_id        = "9876543"
  assume_existing_roles = { "target-account" = "OrganizationAccountAccessRole" } # if it deploys infra
}
```

Everything else (org, state account, default branch, PR access) comes from `github_org` /
`repo_defaults` — add a field to the entry only to deviate. If the repo needs custom
scoped roles in a sub-account, also add a `custom_roles` entry
(`"<account>--<RoleName>"`) listing the repo in `trusted_oidc_repos`.

## 3. Apply and read the plan

Expect: one new IAM role + one inline `AssumeRoles` policy in the management account, and
one S3 state role in the state account (via the sub-account module). Nothing else should
change.

## 4. Wire the repo's workflow

Every value the workflow needs is in the `workflow_config` output:

```sh
tofu output -json workflow_config | jq '."my-new-repo"'
```

- `role_to_assume` → `aws-actions/configure-aws-credentials` `role-to-assume` — the
  ONLY role a workflow ever assumes via OIDC
- `state_role_arn` → the backend's `role_arn`
- `state_prefix`   → the backend key prefix (`<state_prefix>/terraform.tfstate`)
- `existing_role_arns.<account>` → the provider `assume_role` role (or second-hop role)
  for that account
- `custom_role_arns.<role>` → scoped roles for chained jobs

### Reaching downstream accounts

Downstream roles (infra, custom, state) trust the repo's **management role**, not the
OIDC provider — pasting their ARN straight into `role-to-assume` fails. Chain through
the management role:

```yaml
permissions:
  id-token: write
  contents: read
steps:
  - uses: aws-actions/configure-aws-credentials@v5
    with:
      role-to-assume: ${{ vars.OIDC_ROLE }} # workflow_config: role_to_assume
      aws-region: us-east-1

  # Second hop — the downstream role this job needs:
  - uses: aws-actions/configure-aws-credentials@v5
    with:
      role-to-assume: ${{ vars.DNS_ROLE }} # workflow_config: custom_role_arns / existing_role_arns
      role-chaining: true
      aws-region: us-east-1
```

For OpenTofu jobs the second hop is usually implicit: put `state_role_arn` in the
backend's `role_arn` and the infra role in the provider's `assume_role` block — only
non-tofu jobs (CLI/SDK) need explicit chaining.

## If AssumeRoleWithWebIdentity fails

1. **Wrong repo_id / org id** — compare the token's claims against the entry; the repo's
   Settings → Actions → OIDC page previews the exact `sub`.
2. **PR-triggered run without PR access** — PR events mint a `:pull_request` sub; the repo
   (or `repo_defaults`) needs `allow_pull_requests = true`.
3. **Workflow not on the default branch** — only `ref:refs/heads/<default_branch>` runs are
   accepted by default; other branches/tags/environments need `override_subs`.
4. **Second hop fails (`sts:AssumeRole` denied)** — the downstream role must exist:
   has the sub-account module been applied in that account? And are you chaining
   through the management role rather than assuming the downstream role directly via
   OIDC?
5. Compare the `expected_subs` output for the repo against the sub the token actually
   carries — they must match one pattern exactly.
