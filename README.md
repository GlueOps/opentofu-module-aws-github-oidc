<!-- BEGIN_TF_DOCS -->
# opentofu-module-aws-github-oidc
Managed by github-org-manager

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_iam_openid_connect_provider.github](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_role.github_oidc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.github_oidc_assume_roles](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.github_oidc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_policy_document.github_oidc_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_github_repos"></a> [github\_repos](#input\_github\_repos) | Map of GitHub repo names to their OIDC configuration | <pre>map(object({<br/>    github_org     = string<br/>    policy_arns    = list(string)<br/>    state_account  = string<br/>    infra_accounts = map(string)<br/>  }))</pre> | n/a | yes |
| <a name="input_s3_state_role_arns"></a> [s3\_state\_role\_arns](#input\_s3\_state\_role\_arns) | Map of repo name to the S3 state role ARN in the sub-account (included in non-admin assume-role policies) | `map(string)` | `{}` | no |
| <a name="input_sub_account_ids"></a> [sub\_account\_ids](#input\_sub\_account\_ids) | Map of sub-account name to account ID (used to build ARNs in inline policies) | `map(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_thumbprint_list"></a> [thumbprint\_list](#input\_thumbprint\_list) | OIDC thumbprints for GitHub Actions (AWS no longer validates these but the field is required) | `list(string)` | <pre>[<br/>  "6938fd4d98bab03faadb97b34396831e3780aea1",<br/>  "1c58a3a8518e8759bf075b76b750d4f2df264fcd"<br/>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | ARN of the GitHub OIDC provider |
| <a name="output_oidc_role_arns"></a> [oidc\_role\_arns](#output\_oidc\_role\_arns) | Map of repo name to OIDC role ARN in the management account |
| <a name="output_oidc_role_names"></a> [oidc\_role\_names](#output\_oidc\_role\_names) | Map of repo name to OIDC role name in the management account |
<!-- END_TF_DOCS -->