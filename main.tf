locals {
  role_name_prefix   = "github-oidc-"
  role_max_length    = 64
  hash_suffix_length = 8
  hash_separator     = "-"

  role_names = { for repo, cfg in var.github_repos : repo =>
    length("${local.role_name_prefix}${repo}") <= local.role_max_length
    ? "${local.role_name_prefix}${repo}"
    : "${local.role_name_prefix}${substr(repo, 0, local.role_max_length - length(local.role_name_prefix) - local.hash_suffix_length - length(local.hash_separator))}${local.hash_separator}${substr(sha256(repo), 0, local.hash_suffix_length)}"
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
        lookup(var.s3_state_role_arns, each.key, null) != null ? [var.s3_state_role_arns[each.key]] : []
      )
    }]
  })
}
