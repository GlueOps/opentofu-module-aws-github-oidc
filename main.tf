locals {
  role_max_length    = 64
  hash_suffix_length = 8
  hash_separator     = "-"

  # Naming helpers
  prefixes = {
    oidc     = "github-oidc-"
    s3_state = "oidc-s3-state-"
    custom   = "oidc-custom-"
  }

  _name = { for prefix_key, prefix in local.prefixes : prefix_key => {
    max_trunk = local.role_max_length - length(prefix) - local.hash_suffix_length - length(local.hash_separator)
  } }

  role_names = { for repo, cfg in var.github_repos : repo =>
    length("${local.prefixes.oidc}${repo}") <= local.role_max_length
    ? "${local.prefixes.oidc}${repo}"
    : "${local.prefixes.oidc}${substr(repo, 0, local._name.oidc.max_trunk)}${local.hash_separator}${substr(sha256(repo), 0, local.hash_suffix_length)}"
  }

  s3_state_role_names = { for repo, cfg in var.github_repos : repo =>
    length("${local.prefixes.s3_state}${repo}") <= local.role_max_length
    ? "${local.prefixes.s3_state}${repo}"
    : "${local.prefixes.s3_state}${substr(repo, 0, local._name.s3_state.max_trunk)}${local.hash_separator}${substr(sha256(repo), 0, local.hash_suffix_length)}"
  }

  custom_role_names = { for key, cfg in var.custom_sub_account_roles : key =>
    length("${local.prefixes.custom}${key}") <= local.role_max_length
    ? "${local.prefixes.custom}${key}"
    : "${local.prefixes.custom}${substr(key, 0, local._name.custom.max_trunk)}${local.hash_separator}${substr(sha256(key), 0, local.hash_suffix_length)}"
  }

  state_prefixes = { for repo, cfg in var.github_repos : repo =>
    "${lower(cfg.github_org)}/${lower(repo)}"
  }

  tags = { for repo, cfg in var.github_repos : repo => merge(
    {
      ManagedBy  = "opentofu"
      Purpose    = "github-actions-oidc"
      GitHubOrg  = cfg.github_org
      GitHubRepo = "${cfg.github_org}/${repo}"
    },
    var.tags,
  ) }
}

# --- OIDC Provider ---

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = var.thumbprint_list

  tags = merge(
    { ManagedBy = "opentofu", Purpose = "github-actions-oidc" },
    var.tags,
  )

  lifecycle {
    precondition {
      condition = alltrue([
        for key, cfg in var.custom_sub_account_roles :
        alltrue([for repo in cfg.trusted_oidc_repos : contains(keys(var.github_repos), repo)])
      ])
      error_message = "custom_sub_account_roles: every trusted_oidc_repos entry must be a key of github_repos."
    }
  }
}

# --- Trust policies ---
#
# Enforcement is the immutable numeric ID claims (repository_owner_id +
# repository_id, StringEquals): present in every GitHub.com token regardless of
# sub format, and immune to org/repo renames and name recycling. The sub
# StringLike is NOT the primary enforcement, but it also satisfies IAM's
# secure-by-default guardrail for token.actions.githubusercontent.com, which
# rejects any trust policy without a non-wildcard-only sub condition. Default
# scope per repo: only workflows on the repo's default branch. PR-triggered
# runs mint a ":pull_request" sub, not the branch ref, so plan-on-PR pipelines
# must opt in per repo with allow_pull_requests = true. Legacy-format
# equivalents are added when immutable_subs_only = false; allowed_subs
# replaces the defaults entirely.

locals {
  github_oidc_trust = { for repo, cfg in var.github_repos : repo => jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud"                 = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:repository_owner_id" = cfg.github_org_id
          "token.actions.githubusercontent.com:repository_id"       = cfg.repo_id
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = coalesce(cfg.allowed_subs, concat(
            var.immutable_subs_only ? [] : concat(
              ["repo:${cfg.github_org}/${repo}:ref:refs/heads/${cfg.default_branch}"],
              cfg.allow_pull_requests ? ["repo:${cfg.github_org}/${repo}:pull_request"] : [],
            ),
            ["repo:${cfg.github_org}@${cfg.github_org_id}/${repo}@${cfg.repo_id}:ref:refs/heads/${cfg.default_branch}"],
            cfg.allow_pull_requests ? ["repo:${cfg.github_org}@${cfg.github_org_id}/${repo}@${cfg.repo_id}:pull_request"] : [],
          ))
        }
      }
    }]
  }) }
}

# --- OIDC Roles ---

resource "aws_iam_role" "github_oidc" {
  for_each           = var.github_repos
  name               = local.role_names[each.key]
  assume_role_policy = local.github_oidc_trust[each.key]
  tags               = local.tags[each.key]
}

# --- Managed policy attachments ---

resource "aws_iam_role_policy_attachment" "github_oidc" {
  for_each = { for pair in flatten([
    for repo, cfg in var.github_repos : [
      for arn in cfg.policy_arns : { key = "${repo}--${arn}", repo = repo, arn = arn }
    ]
  ]) : pair.key => pair }

  role       = aws_iam_role.github_oidc[each.value.repo].name
  policy_arn = each.value.arn
}

# --- Inline assume-role policies ---
#
# Every repo can always assume its own S3 state role, independent of any
# managed policies attached — attaching a managed policy must never silently
# remove state-backend access. Custom sub-account roles that list the repo in
# trusted_oidc_repos are granted here too, so the grant never has to be
# hand-written by the caller.

locals {
  repo_custom_role_arns = { for repo in keys(var.github_repos) : repo => [
    for key, cfg in var.custom_sub_account_roles :
    # "unknown" placeholder never reaches AWS: the precondition below rejects
    # any custom role whose account is missing from sub_account_ids.
    "arn:aws:iam::${try(var.sub_account_ids[cfg.account], "unknown")}:role/${local.custom_role_names[key]}"
    if contains(cfg.trusted_oidc_repos, repo)
  ] }
}

resource "aws_iam_role_policy" "github_oidc_assume_roles" {
  for_each = var.github_repos

  name = "AssumeRoles"
  role = aws_iam_role.github_oidc[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Resource = concat(
        [for acct, role in each.value.infra_accounts : "arn:aws:iam::${try(var.sub_account_ids[acct], null)}:role/${role}"],
        ["arn:aws:iam::${try(var.sub_account_ids[each.value.state_account], null)}:role/${local.s3_state_role_names[each.key]}"],
        local.repo_custom_role_arns[each.key],
      )
    }]
  })

  lifecycle {
    precondition {
      condition = contains(keys(var.sub_account_ids), each.value.state_account) && alltrue([
        for acct in keys(each.value.infra_accounts) : contains(keys(var.sub_account_ids), acct)
        ]) && alltrue([
        for key, cfg in var.custom_sub_account_roles :
        contains(keys(var.sub_account_ids), cfg.account)
        if contains(cfg.trusted_oidc_repos, each.key)
      ])
      error_message = "Repo ${each.key}: state_account (${each.value.state_account}), every infra_accounts key, and the account of every custom role trusting this repo must exist in sub_account_ids."
    }
  }
}
