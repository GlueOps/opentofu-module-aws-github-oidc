# One repo, many accounts: platform-app deploys broadly to two workload
# accounts, changes DNS through a scoped role in a third, and keeps state in a
# fourth — each account with different permissions.

provider "aws" {
  region = "us-east-1"
}

module "github_oidc" {
  source = "../.."

  github_org = { name = "example-org", id = "1234567" }

  repo_defaults = {
    state_account       = "state"
    default_branch      = "main"
    allow_pull_requests = true
  }

  github_repos = [
    {
      repo_name = "platform-app"
      repo_id   = "9876543"

      # Broad access: assume a pre-existing role per account — the role (and
      # therefore the permissions) can differ per account.
      infra_accounts = {
        workloads-prod    = "OrganizationAccountAccessRole" # full admin in prod
        workloads-staging = "StagingDeployRole"             # narrower, pre-existing
      }
    },
  ]

  sub_account_ids = {
    state             = "222222222222"
    workloads-prod    = "111111111111"
    workloads-staging = "333333333333"
    dns               = "444444444444"
  }

  # Scoped access: a purpose-built role this module pair creates and maintains.
  # platform-app can ONLY touch Route53 in the dns account.
  custom_sub_account_roles = {
    "dns--Route53Only" = {
      account            = "dns"
      policy_arns        = ["arn:aws:iam::aws:policy/AmazonRoute53FullAccess"]
      inline_policy      = null
      trusted_oidc_repos = ["platform-app"]
    }
  }
}

# Everything platform-app's workflow needs — including every downstream role
# ARN it may assume, grouped by kind:
#   role_to_assume, state_role_arn, state_prefix,
#   infra_role_arns  = { workloads-prod = "...", workloads-staging = "..." }
#   custom_role_arns = ["arn:...:role/oidc-custom-dns--Route53Only"]
output "platform_app_workflow" {
  value = module.github_oidc.workflow_config["platform-app"]
}
