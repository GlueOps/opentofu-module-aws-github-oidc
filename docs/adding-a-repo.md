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
  infra_accounts = { "target-account" = "OrganizationAccountAccessRole" } # if it deploys infra
}
```

Everything else (org, state account, default branch, PR access) comes from `github_org` /
`repo_defaults` — add a field to the entry only to deviate. If the repo needs custom
scoped roles in a sub-account, also add a `custom_sub_account_roles` entry
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

- `role_to_assume` → `aws-actions/configure-aws-credentials` `role-to-assume`
- `state_role_arn` → the backend's `role_arn`
- `state_prefix`   → the backend key prefix (`<state_prefix>/terraform.tfstate`)

## If AssumeRoleWithWebIdentity fails

1. **Wrong repo_id / org id** — compare the token's claims against the entry; the repo's
   Settings → Actions → OIDC page previews the exact `sub`.
2. **PR-triggered run without PR access** — PR events mint a `:pull_request` sub; the repo
   (or `repo_defaults`) needs `allow_pull_requests = true`.
3. **Workflow not on the default branch** — only `ref:refs/heads/<default_branch>` runs are
   accepted by default; other branches/tags/environments need `allowed_subs`.
4. Compare the `expected_subs` output for the repo against the sub the token actually
   carries — they must match one pattern exactly.
