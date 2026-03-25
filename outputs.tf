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
