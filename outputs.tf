output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "oidc_role_arns" {
  description = "Map of repo name to OIDC role ARN in the management account"
  value       = { for repo, role in aws_iam_role.github_oidc : repo => role.arn }
}

output "oidc_role_names" {
  description = "Map of repo name to OIDC role name in the management account"
  value       = { for repo, role in aws_iam_role.github_oidc : repo => role.name }
}

output "s3_state_role_names" {
  description = "Map of repo name to computed S3 state role name (for use in sub-accounts)"
  value       = local.s3_state_role_names
}

output "custom_role_names" {
  description = "Map of custom role key to computed role name (for use in sub-accounts)"
  value       = local.custom_role_names
}

output "state_prefixes" {
  description = "Map of repo name to S3 state file prefix (org/repo, lowercased)"
  value       = local.state_prefixes
}

output "tags" {
  description = "Map of repo name to computed tags"
  value       = local.tags
}

output "sub_account_inputs" {
  description = "Per-account inputs for the sub-account module, pre-grouped: pass sub_account_inputs[account].repos and .custom_roles straight through — no consumer-side fan-out glue needed. Every account in sub_account_ids has an entry (possibly empty)."
  value = { for acct in keys(var.sub_account_ids) : acct => {
    repos = { for repo, cfg in local.repos : repo => {
      s3_state_role_name = local.s3_state_role_names[repo]
      oidc_role_arn      = aws_iam_role.github_oidc[repo].arn
      state_prefix       = local.state_prefixes[repo]
      tags               = local.tags[repo]
    } if cfg.state_account == acct }
    custom_roles = { for key, cfg in var.custom_sub_account_roles : key => {
      role_name          = local.custom_role_names[key]
      policy_arns        = cfg.policy_arns
      inline_policy      = cfg.inline_policy
      trusted_oidc_repos = cfg.trusted_oidc_repos
      oidc_role_arns     = { for r in cfg.trusted_oidc_repos : r => aws_iam_role.github_oidc[r].arn }
    } if cfg.account == acct }
  } }
}

output "workflow_config" {
  description = "Per-repo values a GitHub Actions workflow needs: the role to assume via OIDC, the state-backend role ARN and key prefix, and the downstream role ARNs it may assume."
  # try() fallbacks never reach consumers: the AssumeRoles precondition
  # rejects any plan whose accounts are missing from sub_account_ids.
  value = { for repo, cfg in local.repos : repo => {
    role_to_assume   = aws_iam_role.github_oidc[repo].arn
    state_role_arn   = "arn:aws:iam::${try(var.sub_account_ids[cfg.state_account], "unknown")}:role/${local.s3_state_role_names[repo]}"
    state_prefix     = local.state_prefixes[repo]
    infra_role_arns  = { for acct, role in cfg.infra_accounts : acct => "arn:aws:iam::${try(var.sub_account_ids[acct], "unknown")}:role/${role}" }
    custom_role_arns = local.repo_custom_role_arns[repo]
  } }
}

output "expected_subs" {
  description = "Per-repo sub-claim patterns the trust policy accepts — diff against the repo's Settings -> Actions -> OIDC sub preview when debugging AssumeRoleWithWebIdentity failures."
  value       = local.sub_patterns
}
