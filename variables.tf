variable "github_repos" {
  description = "Map of GitHub repo names to their OIDC configuration. `github_org_id` and `repo_id` are the immutable numeric GitHub IDs (find them with: gh api repos/ORG/REPO --jq '.id, .owner.id'). The trust policy accepts only workflows on the repo's default branch (`default_branch`, required — e.g. \"main\"); set `allow_pull_requests = true` to also accept pull_request-triggered runs (required for plan-on-PR pipelines). `allowed_subs` replaces the default sub-claim patterns entirely."
  type = map(object({
    github_org          = string
    github_org_id       = string
    repo_id             = string
    policy_arns         = list(string)
    state_account       = string
    infra_accounts      = map(string)
    default_branch      = string
    allow_pull_requests = optional(bool, false)
    allowed_subs        = optional(list(string))
  }))

  validation {
    condition = alltrue([
      for cfg in values(var.github_repos) :
      can(regex("^[0-9]+$", cfg.github_org_id)) && can(regex("^[0-9]+$", cfg.repo_id))
    ])
    error_message = "github_org_id and repo_id must be numeric GitHub IDs passed as strings — the REST API numeric ids, not GraphQL node IDs. Find them with: gh api repos/ORG/REPO --jq '.id, .owner.id'."
  }

  validation {
    condition     = alltrue([for cfg in values(var.github_repos) : length(cfg.default_branch) > 0])
    error_message = "default_branch must be a non-empty branch name (e.g. \"main\")."
  }
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

variable "immutable_subs_only" {
  description = "DEPRECATED: transitional escape hatch only — will be removed in a future major version. Leave unset (true). Setting false adds legacy name-based equivalents of the default sub patterns, needed only while repos created before 2026-07-15 have not opted into immutable subject claims (the use_immutable_subject OIDC setting) — opt those repos in instead. Has no effect on repos that set allowed_subs."
  type        = bool
  default     = true
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
