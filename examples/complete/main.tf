provider "aws" {
  region = "us-east-1"
}

module "github_oidc" {
  source = "../.."

  github_repos = {
    # Simple: role assumable by any workflow in the repo, deploys via an
    # infra-account role, state in the state account.
    "demo-app" = {
      github_org     = "example-org"
      github_org_id  = "1234567" # gh api orgs/example-org --jq .id
      repo_id        = "9876543" # gh api repos/example-org/demo-app --jq .id
      policy_arns    = []
      state_account  = "state"
      infra_accounts = { core = "OrganizationAccountAccessRole" }

      default_branch      = "main"
      allow_pull_requests = true # PR-triggered plans may assume the role too
      allowed_subs        = null # declared-but-unused: default sub patterns apply
    }

    # Managed policies in the management account, sub scoped to main.
    "org-admin" = {
      github_org     = "example-org"
      github_org_id  = "1234567"
      repo_id        = "9876544"
      policy_arns    = ["arn:aws:iam::aws:policy/AdministratorAccess"]
      state_account  = "state"
      infra_accounts = {}
      default_branch = "main"
      allowed_subs   = ["repo:example-org@1234567/org-admin@9876544:ref:refs/heads/main"]
    }
  }

  sub_account_ids = {
    core  = "111111111111"
    state = "222222222222"
  }

  custom_sub_account_roles = {
    "core--Route53Access" = {
      account            = "core"
      policy_arns        = ["arn:aws:iam::aws:policy/AmazonRoute53FullAccess"]
      inline_policy      = null
      trusted_oidc_repos = ["demo-app"]
    }
  }

  tags = { Team = "platform" }
}

output "oidc_role_arns" {
  value = module.github_oidc.oidc_role_arns
}
