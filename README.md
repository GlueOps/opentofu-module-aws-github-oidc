<!-- BEGIN_TF_DOCS -->
# opentofu-module-aws-github-oidc

OpenTofu module that sets up GitHub Actions OIDC authentication for AWS. Creates the OIDC provider, per-repo IAM roles with trust policies, managed policy attachments, and scoped assume-role inline policies in the **management account**.

## How it works

This module is one half of a two-module setup:

1. **This module** (`opentofu-module-aws-github-oidc`) — runs in the AWS management account. Creates the GitHub OIDC provider and per-repo IAM roles that GitHub Actions workflows assume via `AssumeRoleWithWebIdentity`.

2. **[opentofu-module-aws-github-oidc-sub-account](https://github.com/GlueOps/opentofu-module-aws-github-oidc-sub-account)** — runs in each AWS sub-account. Creates scoped S3 state roles (per-repo, locked to their own state file prefix) and optional custom roles with configurable policies. Receives the provider from the caller via `configuration_aliases`.

```
GitHub Actions Workflow
  |
  | (OIDC AssumeRoleWithWebIdentity)
  v
Management Account IAM Role (this module)
  |
  | (sts:AssumeRole)
  v
Sub-Account Roles (sub-account module)
  ├── S3 State Role: scoped to repo's state file prefix
  ├── Infrastructure Role: e.g., OrganizationAccountAccessRole
  └── Custom Roles: e.g., Route53-only, RDS-only
```

## Usage

```hcl
provider "aws" {
  alias    = "sub_account"
  for_each = local.sub_account_config
  region   = each.value.region
  assume_role {
    role_arn = "arn:aws:iam::${each.value.account_id}:role/OrganizationAccountAccessRole"
  }
}

module "github_oidc" {
  source = "git::https://github.com/GlueOps/opentofu-module-aws-github-oidc.git?ref=main"

  github_org = { name = "MyOrg", id = "1234567" } # id: gh api orgs/MyOrg --jq .id

  repo_defaults = {
    state_account       = "my-state-account"
    default_branch      = "main"
    allow_pull_requests = true # PR-triggered plans may assume the roles
  }

  # Only what varies per repo. repo_id: gh api repos/MyOrg/<repo> --jq .id
  github_repos = [
    {
      repo_name      = "my-repo"
      repo_id        = "9876543"
      infra_accounts = { "my-sub-account" = "OrganizationAccountAccessRole" }
    },
    { repo_name = "another-repo", repo_id = "9876544" },
  ]

  sub_account_ids          = { "my-sub-account" = "123456789012", "my-state-account" = "987654321098" }
  custom_sub_account_roles = {}
}

module "github_oidc_sub_account" {
  source   = "git::https://github.com/GlueOps/opentofu-module-aws-github-oidc-sub-account.git?ref=main"
  for_each = toset(keys(local.sub_account_config))

  providers = { aws = aws.sub_account[each.key] }

  repos        = module.github_oidc.sub_account_inputs[each.key].repos
  custom_roles = module.github_oidc.sub_account_inputs[each.key].custom_roles
}
```

See [docs/adding-a-repo.md](docs/adding-a-repo.md) for the end-to-end runbook, and the
`workflow_config` output for the exact values (role ARN, state-role ARN, state key prefix)
each repo's GitHub Actions workflow needs.

## Defaults and overrides

`github_org` and `repo_defaults` apply to every entry in `github_repos`; any per-repo
field overrides them. `allowed_subs` is deliberately not defaultable — sub-scope overrides
must stay visible on the repo entry. The idiom is: an entry shows only what deviates, so
every line in it is a grant or an exception.

## Role naming

All role names are auto-generated with a friendly prefix. If the name exceeds 64 characters (IAM limit), it's truncated with a SHA256 hash suffix for uniqueness:

| Role type | Prefix | Example |
|-----------|--------|---------|
| OIDC (management account) | `github-oidc-` | `github-oidc-my-repo` |
| S3 state (sub-account) | `oidc-s3-state-` | `oidc-s3-state-my-repo` |
| Custom (sub-account) | `oidc-custom-` | `oidc-custom-my-account--Route53Access` |

## Trust policy model

Roles are trusted to the **immutable numeric GitHub IDs** (`repository_owner_id` and
`repository_id`, exact match) rather than the mutable `org/repo` name — immune to
renames, transfers, and name recycling, and compatible with both the legacy and the
post-2026-07-15 immutable `sub` formats. A `sub` condition is kept because IAM requires
one for the GitHub OIDC provider; it scopes each repo to its default branch (resolved from
`repo_defaults.default_branch` or the entry's `default_branch`), with pull\_request-triggered
runs opt-in per repo and `allowed_subs` replacing it entirely. See [MIGRATION.md](MIGRATION.md) for the v0 -> v1 upgrade and the
behavioral details (transfers fail closed until IDs are updated).

Scope: GitHub.com only (GHES/data-residency tenants use a different issuer); the ID
condition keys are supported by AWS in commercial partitions.

## Custom sub-account roles

Roles declared in `custom_sub_account_roles` are created by the sub-account module; this
module automatically grants each repo listed in a role's `trusted_oidc_repos` permission to
assume it — no hand-written grant policies needed in the caller.

## Branch / environment scoping (`allowed_subs`)

By default a repo's role is assumable only by workflows on the repo's default branch
(resolved from `repo_defaults.default_branch` or the entry's `default_branch`):

```
repo:MyOrg@1234567/my-repo@9876543:ref:refs/heads/main
```

Pull-request-triggered runs mint a `:pull_request` sub context rather than a branch ref,
so they are rejected by default. Pipelines that plan on PRs must opt in per repo with
`allow_pull_requests = true`, which adds:

```
repo:MyOrg@1234567/my-repo@9876543:pull_request
```

Workflows on other branches, tags, or environment-gated jobs (`...:environment:NAME`) are
always rejected by default. To scope a repo differently, set `allowed_subs` with exact sub
patterns (immutable format, matched as minted by the repo) — it replaces the defaults
entirely, e.g. to allow an environment add its `...:environment:NAME` sub.

`allowed_subs = null` behaves exactly like omitting the attribute (the default patterns
apply). With `repo_defaults` in play, prefer omitting defaults entirely: an entry should
show only what deviates.

## Legacy sub pattern (deprecated)

By default the trust-policy sub condition uses only the immutable `repo:ORG@ID/*` pattern.
`immutable_subs_only = false` is a **deprecated** transitional escape hatch that adds
legacy name-based equivalents of the default sub patterns, for repos created before
2026-07-15 that have not opted into immutable subject claims (the `use_immutable_subject`
OIDC setting). Prefer opting those repos in instead — the variable will be removed in a
future major version.

## Multi-org support

Set the module-level `github_org` for the common case; individual entries may override `github_org`/`github_org_id`, so repos from different GitHub organizations can coexist in the same configuration.

## Deleting a sub-account

Removing a sub-account is a two-step process:

1. Remove all repos and custom roles that reference the account. Apply.
2. Remove the sub-account from the config and provider. Apply.

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.60.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_iam_openid_connect_provider.github](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_role.github_oidc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.github_oidc_assume_roles](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.github_oidc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_custom_sub_account_roles"></a> [custom\_sub\_account\_roles](#input\_custom\_sub\_account\_roles) | Custom roles to create in sub-accounts | <pre>map(object({<br/>    account            = string<br/>    policy_arns        = list(string)<br/>    inline_policy      = optional(string)<br/>    trusted_oidc_repos = list(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_github_org"></a> [github\_org](#input\_github\_org) | Default GitHub organization for all repos: name and immutable numeric ID (gh api orgs/ORG --jq .id). Individual repos may override via their github\_org/github\_org\_id fields (multi-org setups). | <pre>object({<br/>    name = string<br/>    id   = string<br/>  })</pre> | `null` | no |
| <a name="input_github_repos"></a> [github\_repos](#input\_github\_repos) | GitHub repos to create OIDC roles for. `repo_id` (and, when overriding, `github_org_id`) are the immutable numeric GitHub IDs — find them with: gh api repos/ORG/REPO --jq '.id, .owner.id'. Per-repo values override `github_org` / `repo_defaults`. The trust policy accepts only workflows on the repo's default branch; `allow_pull_requests = true` also accepts pull\_request-triggered runs (required for plan-on-PR pipelines), and `allowed_subs` replaces the default sub-claim patterns entirely. | <pre>list(object({<br/>    repo_name           = string<br/>    repo_id             = string<br/>    github_org          = optional(string)<br/>    github_org_id       = optional(string)<br/>    policy_arns         = optional(list(string), [])<br/>    state_account       = optional(string)<br/>    infra_accounts      = optional(map(string), {})<br/>    default_branch      = optional(string)<br/>    allow_pull_requests = optional(bool)<br/>    allowed_subs        = optional(list(string))<br/>  }))</pre> | n/a | yes |
| <a name="input_immutable_subs_only"></a> [immutable\_subs\_only](#input\_immutable\_subs\_only) | DEPRECATED: transitional escape hatch only — will be removed in a future major version. Leave unset (true). Setting false adds legacy name-based equivalents of the default sub patterns, needed only while repos created before 2026-07-15 have not opted into immutable subject claims (the use\_immutable\_subject OIDC setting) — opt those repos in instead. Has no effect on repos that set allowed\_subs. | `bool` | `true` | no |
| <a name="input_repo_defaults"></a> [repo\_defaults](#input\_repo\_defaults) | Defaults applied to every github\_repos entry unless the entry sets its own value. allowed\_subs is deliberately not defaultable — sub-scope overrides must stay visible per repo. | <pre>object({<br/>    state_account       = optional(string)<br/>    default_branch      = optional(string)<br/>    allow_pull_requests = optional(bool)<br/>  })</pre> | `{}` | no |
| <a name="input_sub_account_ids"></a> [sub\_account\_ids](#input\_sub\_account\_ids) | Map of sub-account name to account ID (used to build ARNs in inline policies) | `map(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_thumbprint_list"></a> [thumbprint\_list](#input\_thumbprint\_list) | OIDC thumbprints for GitHub Actions (AWS no longer validates these but the field is required) | `list(string)` | <pre>[<br/>  "6938fd4d98bab03faadb97b34396831e3780aea1",<br/>  "1c58a3a8518e8759bf075b76b750d4f2df264fcd"<br/>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_custom_role_names"></a> [custom\_role\_names](#output\_custom\_role\_names) | Map of custom role key to computed role name (for use in sub-accounts) |
| <a name="output_expected_subs"></a> [expected\_subs](#output\_expected\_subs) | Per-repo sub-claim patterns the trust policy accepts — diff against the repo's Settings -> Actions -> OIDC sub preview when debugging AssumeRoleWithWebIdentity failures. |
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | ARN of the GitHub OIDC provider |
| <a name="output_oidc_role_arns"></a> [oidc\_role\_arns](#output\_oidc\_role\_arns) | Map of repo name to OIDC role ARN in the management account |
| <a name="output_oidc_role_names"></a> [oidc\_role\_names](#output\_oidc\_role\_names) | Map of repo name to OIDC role name in the management account |
| <a name="output_s3_state_role_names"></a> [s3\_state\_role\_names](#output\_s3\_state\_role\_names) | Map of repo name to computed S3 state role name (for use in sub-accounts) |
| <a name="output_state_prefixes"></a> [state\_prefixes](#output\_state\_prefixes) | Map of repo name to S3 state file prefix (org/repo, lowercased) |
| <a name="output_sub_account_inputs"></a> [sub\_account\_inputs](#output\_sub\_account\_inputs) | Per-account inputs for the sub-account module, pre-grouped: pass sub\_account\_inputs[account].repos and .custom\_roles straight through — no consumer-side fan-out glue needed. Every account in sub\_account\_ids has an entry (possibly empty). |
| <a name="output_tags"></a> [tags](#output\_tags) | Map of repo name to computed tags |
| <a name="output_workflow_config"></a> [workflow\_config](#output\_workflow\_config) | Per-repo values a GitHub Actions workflow needs: the role to assume via OIDC, the state-backend role ARN and key prefix, and the downstream role ARNs it may assume. |
<!-- END_TF_DOCS -->