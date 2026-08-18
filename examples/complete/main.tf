provider "aws" {
  region = "us-east-1"
}

module "github_oidc" {
  source = "../.."

  github_org = { name = "example-org", id = "1234567" } # gh api orgs/example-org --jq .id

  repo_defaults = {
    state_account       = "state"
    default_branch      = "main"
    allow_pull_requests = true # PR-triggered plans may assume the roles
  }

  # Only what varies per repo. repo_id: gh api repos/example-org/<repo> --jq .id
  github_repos = [
    # Deploys via an infra-account role, state in the state account.
    {
      repo_name             = "demo-app"
      repo_id               = "9876543"
      assume_existing_roles = { core = "OrganizationAccountAccessRole" }
    },
    # Managed policies in the management account, sub scoped to main only
    # (override_subs replaces the defaults — no PR access for this one).
    {
      repo_name     = "org-admin"
      repo_id       = "9876544"
      policy_arns   = ["arn:aws:iam::aws:policy/AdministratorAccess"]
      override_subs = ["repo:example-org@1234567/org-admin@9876544:ref:refs/heads/main"]
    },
  ]

  account_ids = {
    core  = "111111111111"
    state = "222222222222"
  }

  custom_roles = {
    core = {
      Route53Access = {
        policy_arns        = ["arn:aws:iam::aws:policy/AmazonRoute53FullAccess"]
        trusted_oidc_repos = ["demo-app"]
      }
    }
  }

  tags = { Team = "platform" }
}

output "workflow_config" {
  value = module.github_oidc.workflow_config
}
