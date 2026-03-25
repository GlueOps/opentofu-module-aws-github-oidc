variable "github_repos" {
  description = "Map of GitHub repo names to their OIDC configuration"
  type = map(object({
    github_org     = string
    policy_arns    = list(string)
    state_account  = string
    infra_accounts = map(string)
  }))
}

variable "sub_account_ids" {
  description = "Map of sub-account name to account ID (used to build ARNs in inline policies)"
  type        = map(string)
}

variable "custom_sub_account_roles" {
  description = "Custom roles to create in sub-accounts"
  type = map(object({
    account            = string
    policy_arns        = list(string)
    inline_policy      = optional(string)
    trusted_oidc_repos = list(string)
  }))
  default = {}
}

variable "thumbprint_list" {
  description = "OIDC thumbprints for GitHub Actions (AWS no longer validates these but the field is required)"
  type        = list(string)
  default = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
