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

  github_repos = {
    "my-repo" = {
      github_org     = "MyOrg"
      github_org_id  = "1234567" # numeric owner ID: gh api orgs/MyOrg --jq .id
      repo_id        = "9876543" # numeric repo ID:  gh api repos/MyOrg/my-repo --jq .id
      policy_arns    = []
      state_account  = "my-state-account"
      infra_accounts = {
        "my-sub-account" = "OrganizationAccountAccessRole"
      }
    }
  }

  sub_account_ids          = { "my-sub-account" = "123456789012", "my-state-account" = "987654321098" }
  custom_sub_account_roles = {}
}

module "github_oidc_sub_account" {
  source   = "git::https://github.com/GlueOps/opentofu-module-aws-github-oidc-sub-account.git?ref=main"
  for_each = toset(keys(local.sub_account_config))

  providers = { aws = aws.sub_account[each.key] }

  repos = { for repo, cfg in local.github_repos : repo => {
    s3_state_role_name = module.github_oidc.s3_state_role_names[repo]
    oidc_role_arn      = module.github_oidc.oidc_role_arns[repo]
    state_prefix       = module.github_oidc.state_prefixes[repo]
    tags               = module.github_oidc.tags[repo]
  } if cfg.state_account == each.key }

  custom_roles = {}
}
```

## Role naming

All role names are auto-generated with a friendly prefix. If the name exceeds 64 characters (IAM limit), it's truncated with a SHA256 hash suffix for uniqueness:

| Role type | Prefix | Example |
|-----------|--------|---------|
| OIDC (management account) | `github-oidc-` | `github-oidc-my-repo` |
| S3 state (sub-account) | `oidc-s3-state-` | `oidc-s3-state-my-repo` |
| Custom (sub-account) | `oidc-custom-` | `oidc-custom-my-account--Route53Access` |

## Trust policy model (v1)

Roles are trusted to the **immutable numeric GitHub IDs** (`repository_owner_id` and
`repository_id`, exact match) rather than the mutable `org/repo` name — immune to
renames, transfers, and name recycling, and compatible with both the legacy and the
post-2026-07-15 immutable `sub` formats. An org-scoped `sub` condition is kept because
IAM requires one for the GitHub OIDC provider; scope it tighter per repo with
`allowed_subs`. See [MIGRATION.md](MIGRATION.md) for the v0 -> v1 upgrade and the
behavioral details (transfers fail closed until IDs are updated).

Scope: GitHub.com only (GHES/data-residency tenants use a different issuer); the ID
condition keys are supported by AWS in commercial partitions.

## Custom sub-account roles

Roles declared in `custom_sub_account_roles` are created by the sub-account module; this
module automatically grants each repo listed in a role's `trusted_oidc_repos` permission to
assume it — no hand-written grant policies needed in the caller.

## Legacy sub pattern

By default the trust-policy sub condition uses only the immutable `repo:ORG@ID/*` pattern.
If some of your repos were created before 2026-07-15 and have not opted into immutable
subject claims (the `use_immutable_subject` OIDC setting), set
`immutable_subs_only = false` to also include the legacy name-based `repo:ORG/*` pattern —
then flip it back once every repo is opted in.

## Multi-org support

Each repo specifies its own `github_org`, so repos from different GitHub organizations can coexist in the same configuration.

## Deleting a sub-account

Removing a sub-account is a two-step process:

1. Remove all repos and custom roles that reference the account. Apply.
2. Remove the sub-account from the config and provider. Apply.

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
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
| <a name="input_github_repos"></a> [github\_repos](#input\_github\_repos) | Map of GitHub repo names to their OIDC configuration. `github_org_id` and `repo_id` are the immutable numeric GitHub IDs (find them with: gh api repos/ORG/REPO --jq '.id, .owner.id'). `allowed_subs` optionally overrides the default sub-claim patterns (e.g. to scope to a branch or environment). | <pre>map(object({<br/>    github_org     = string<br/>    github_org_id  = string<br/>    repo_id        = string<br/>    policy_arns    = list(string)<br/>    state_account  = string<br/>    infra_accounts = map(string)<br/>    allowed_subs   = optional(list(string))<br/>  }))</pre> | n/a | yes |
| <a name="input_immutable_subs_only"></a> [immutable\_subs\_only](#input\_immutable\_subs\_only) | When true (default), the default trust-policy sub condition uses only the immutable repo:ORG@ID/* pattern. Set to false to also include the legacy name-based repo:ORG/* pattern — needed only while repos created before 2026-07-15 have not opted into immutable subject claims (the use\_immutable\_subject OIDC setting). Has no effect on repos that set allowed\_subs. | `bool` | `true` | no |
| <a name="input_sub_account_ids"></a> [sub\_account\_ids](#input\_sub\_account\_ids) | Map of sub-account name to account ID (used to build ARNs in inline policies) | `map(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_thumbprint_list"></a> [thumbprint\_list](#input\_thumbprint\_list) | OIDC thumbprints for GitHub Actions (AWS no longer validates these but the field is required) | `list(string)` | <pre>[<br/>  "6938fd4d98bab03faadb97b34396831e3780aea1",<br/>  "1c58a3a8518e8759bf075b76b750d4f2df264fcd"<br/>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_custom_role_names"></a> [custom\_role\_names](#output\_custom\_role\_names) | Map of custom role key to computed role name (for use in sub-accounts) |
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | ARN of the GitHub OIDC provider |
| <a name="output_oidc_role_arns"></a> [oidc\_role\_arns](#output\_oidc\_role\_arns) | Map of repo name to OIDC role ARN in the management account |
| <a name="output_oidc_role_names"></a> [oidc\_role\_names](#output\_oidc\_role\_names) | Map of repo name to OIDC role name in the management account |
| <a name="output_s3_state_role_names"></a> [s3\_state\_role\_names](#output\_s3\_state\_role\_names) | Map of repo name to computed S3 state role name (for use in sub-accounts) |
| <a name="output_state_prefixes"></a> [state\_prefixes](#output\_state\_prefixes) | Map of repo name to S3 state file prefix (org/repo, lowercased) |
| <a name="output_tags"></a> [tags](#output\_tags) | Map of repo name to computed tags |
<!-- END_TF_DOCS -->