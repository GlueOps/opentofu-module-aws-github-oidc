variable "github_repos" {
  description = "GitHub repos to create OIDC roles for. `repo_id` (and, when overriding, `github_org_id`) are the immutable numeric GitHub IDs — find them with: gh api repos/ORG/REPO --jq '.id, .owner.id'. Per-repo values override `github_org` / `repo_defaults`. The trust policy accepts only workflows on the repo's default branch; `allow_pull_requests = true` also accepts pull_request-triggered runs (required for plan-on-PR pipelines), and `override_subs` replaces the default sub-claim patterns entirely."
  type = list(object({
    repo_name             = string
    repo_id               = string
    github_org            = optional(string)
    github_org_id         = optional(string)
    policy_arns           = optional(list(string), [])
    state_account         = optional(string)
    assume_existing_roles = optional(map(string), {})
    default_branch        = optional(string)
    allow_pull_requests   = optional(bool)
    override_subs         = optional(list(string))
  }))

  validation {
    condition     = length(var.github_repos) == length(distinct([for r in var.github_repos : r.repo_name]))
    error_message = "github_repos: repo_name values must be unique."
  }

  validation {
    condition     = alltrue([for r in var.github_repos : can(regex("^[0-9]+$", r.repo_id))])
    error_message = "repo_id must be the numeric GitHub repository ID passed as a string — the REST API numeric id, not a GraphQL node ID. Find it with: gh api repos/ORG/REPO --jq .id."
  }

  validation {
    condition = alltrue([
      for r in var.github_repos :
      (r.github_org != null ? r.github_org : try(var.github_org.name, null)) != null &&
      can(regex("^[0-9]+$", r.github_org_id != null ? r.github_org_id : try(var.github_org.id, "")))
    ])
    error_message = "Every repo must resolve a GitHub org name and numeric org ID — set the module-level github_org = { name, id }, or github_org/github_org_id on the repo entry."
  }

  validation {
    condition = alltrue([
      for r in var.github_repos :
      length(r.default_branch != null ? r.default_branch : (var.repo_defaults.default_branch != null ? var.repo_defaults.default_branch : "")) > 0
    ])
    error_message = "Every repo must resolve a non-empty default_branch — set repo_defaults.default_branch or default_branch on the repo entry."
  }

  validation {
    condition = alltrue([
      for r in var.github_repos :
      (r.state_account != null ? r.state_account : var.repo_defaults.state_account) != null
    ])
    error_message = "Every repo must resolve a state_account — set repo_defaults.state_account or state_account on the repo entry."
  }
}

variable "github_org" {
  description = "Default GitHub organization for all repos: name and immutable numeric ID (gh api orgs/ORG --jq .id). Individual repos may override via their github_org/github_org_id fields (multi-org setups)."
  type = object({
    name = string
    id   = string
  })
  default = null
}

variable "repo_defaults" {
  description = "Defaults applied to every github_repos entry unless the entry sets its own value. override_subs is deliberately not defaultable — sub-scope overrides must stay visible per repo."
  type = object({
    state_account       = optional(string)
    default_branch      = optional(string)
    allow_pull_requests = optional(bool)
  })
  default = {}
}

variable "account_ids" {
  description = "Map of account name to account ID for every account referenced by state_account, assume_existing_roles, or custom_roles — including the management account when roles live there."
  type        = map(string)
}

variable "custom_roles" {
  description = "Scoped roles this module pair creates, grouped by account: account name => role name => config. Each repo listed in trusted_oidc_repos is granted sts:AssumeRole on the role automatically. Role names render as oidc-custom-<account>--<RoleName>."
  type = map(map(object({
    policy_arns        = list(string)
    inline_policy      = optional(string)
    trusted_oidc_repos = list(string)
  })))
  default = {}

  validation {
    condition = alltrue([
      for acct, roles in var.custom_roles : alltrue([
        for name, cfg in roles :
        alltrue([for r in cfg.trusted_oidc_repos : contains([for gr in var.github_repos : gr.repo_name], r)])
      ])
    ])
    error_message = "custom_roles: every trusted_oidc_repos entry must match a repo_name in github_repos."
  }

  validation {
    condition     = alltrue([for acct in keys(var.custom_roles) : contains(keys(var.account_ids), acct)])
    error_message = "custom_roles: every account key must exist in account_ids."
  }
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
