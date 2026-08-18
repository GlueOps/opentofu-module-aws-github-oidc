locals {
  # Per-repo config with github_org / repo_defaults resolved. Keyed by
  # repo_name — every resource for_each below uses these keys, so they must
  # never change shape (state addresses depend on them).
  repos = { for r in var.github_repos : r.repo_name => {
    repo_id               = r.repo_id
    github_org            = r.github_org != null ? r.github_org : var.github_org.name
    github_org_id         = r.github_org_id != null ? r.github_org_id : var.github_org.id
    policy_arns           = r.policy_arns
    state_account         = r.state_account != null ? r.state_account : var.repo_defaults.state_account
    assume_existing_roles = r.assume_existing_roles
    default_branch        = r.default_branch != null ? r.default_branch : var.repo_defaults.default_branch
    allow_pull_requests   = r.allow_pull_requests != null ? r.allow_pull_requests : coalesce(var.repo_defaults.allow_pull_requests, false)
    override_subs         = r.override_subs
  } }
}

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

  role_names = { for repo, cfg in local.repos : repo =>
    length("${local.prefixes.oidc}${repo}") <= local.role_max_length
    ? "${local.prefixes.oidc}${repo}"
    : "${local.prefixes.oidc}${substr(repo, 0, local._name.oidc.max_trunk)}${local.hash_separator}${substr(sha256(repo), 0, local.hash_suffix_length)}"
  }

  s3_state_role_names = { for repo, cfg in local.repos : repo =>
    length("${local.prefixes.s3_state}${repo}") <= local.role_max_length
    ? "${local.prefixes.s3_state}${repo}"
    : "${local.prefixes.s3_state}${substr(repo, 0, local._name.s3_state.max_trunk)}${local.hash_separator}${substr(sha256(repo), 0, local.hash_suffix_length)}"
  }

  custom_role_names = { for key, cfg in var.custom_roles : key =>
    length("${local.prefixes.custom}${key}") <= local.role_max_length
    ? "${local.prefixes.custom}${key}"
    : "${local.prefixes.custom}${substr(key, 0, local._name.custom.max_trunk)}${local.hash_separator}${substr(sha256(key), 0, local.hash_suffix_length)}"
  }

  state_prefixes = { for repo, cfg in local.repos : repo =>
    "${lower(cfg.github_org)}/${lower(repo)}"
  }

  tags = { for repo, cfg in local.repos : repo => merge(
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
# equivalents are added when immutable_subs_only = false; override_subs
# replaces the defaults entirely.

locals {
  sub_patterns = { for repo, cfg in local.repos : repo => coalesce(cfg.override_subs, concat(
    var.immutable_subs_only ? [] : concat(
      ["repo:${cfg.github_org}/${repo}:ref:refs/heads/${cfg.default_branch}"],
      cfg.allow_pull_requests ? ["repo:${cfg.github_org}/${repo}:pull_request"] : [],
    ),
    ["repo:${cfg.github_org}@${cfg.github_org_id}/${repo}@${cfg.repo_id}:ref:refs/heads/${cfg.default_branch}"],
    cfg.allow_pull_requests ? ["repo:${cfg.github_org}@${cfg.github_org_id}/${repo}@${cfg.repo_id}:pull_request"] : [],
  )) }

  github_oidc_trust = { for repo, cfg in local.repos : repo => jsonencode({
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
          "token.actions.githubusercontent.com:sub" = local.sub_patterns[repo]
        }
      }
    }]
  }) }
}

# --- OIDC Roles ---

resource "aws_iam_role" "github_oidc" {
  for_each           = local.repos
  name               = local.role_names[each.key]
  assume_role_policy = local.github_oidc_trust[each.key]
  tags               = local.tags[each.key]
}

# --- Managed policy attachments ---

resource "aws_iam_role_policy_attachment" "github_oidc" {
  for_each = { for pair in flatten([
    for repo, cfg in local.repos : [
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
  repo_custom_role_arns = { for repo in keys(local.repos) : repo => {
    for key, cfg in var.custom_roles :
    # "unknown" placeholder never reaches AWS: the precondition below rejects
    # any custom role whose account is missing from account_ids.
    key => "arn:aws:iam::${try(var.account_ids[cfg.account], "unknown")}:role/${local.custom_role_names[key]}"
    if contains(cfg.trusted_oidc_repos, repo)
  } }
}

resource "aws_iam_role_policy" "github_oidc_assume_roles" {
  for_each = local.repos

  name = "AssumeRoles"
  role = aws_iam_role.github_oidc[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Resource = concat(
        [for acct, role in each.value.assume_existing_roles : "arn:aws:iam::${try(var.account_ids[acct], null)}:role/${role}"],
        ["arn:aws:iam::${try(var.account_ids[each.value.state_account], null)}:role/${local.s3_state_role_names[each.key]}"],
        values(local.repo_custom_role_arns[each.key]),
      )
    }]
  })

  lifecycle {
    precondition {
      condition = contains(keys(var.account_ids), each.value.state_account) && alltrue([
        for acct in keys(each.value.assume_existing_roles) : contains(keys(var.account_ids), acct)
        ]) && alltrue([
        for key, cfg in var.custom_roles :
        contains(keys(var.account_ids), cfg.account)
        if contains(cfg.trusted_oidc_repos, each.key)
      ])
      error_message = "Repo ${each.key}: state_account (${each.value.state_account}), every assume_existing_roles key, and the account of every custom role trusting this repo must exist in account_ids."
    }
  }
}
