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
}

# --- Trust policies ---

data "aws_iam_policy_document" "github_oidc_trust" {
  for_each = var.github_repos

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${each.value.github_org}/${each.key}:*"]
    }
  }
}

# --- OIDC Roles ---

resource "aws_iam_role" "github_oidc" {
  for_each           = var.github_repos
  name               = local.role_names[each.key]
  assume_role_policy = data.aws_iam_policy_document.github_oidc_trust[each.key].json
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

# --- Inline assume-role policies for non-admin repos ---

resource "aws_iam_role_policy" "github_oidc_assume_roles" {
  for_each = { for repo, cfg in var.github_repos : repo => cfg if length(cfg.policy_arns) == 0 }

  name = "AssumeRoles"
  role = aws_iam_role.github_oidc[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Resource = concat(
        [for acct, role in each.value.infra_accounts : "arn:aws:iam::${var.sub_account_ids[acct]}:role/${role}"],
        ["arn:aws:iam::${var.sub_account_ids[each.value.state_account]}:role/${local.s3_state_role_names[each.key]}"]
      )
    }]
  })
}
