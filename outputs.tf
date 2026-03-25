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
