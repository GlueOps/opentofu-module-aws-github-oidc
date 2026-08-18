# One repo, many accounts: platform-app deploys broadly to two workload
# accounts, changes DNS through a scoped role in a third, and keeps state in a
# fourth — each account with different permissions.
#
# BOTH modules are required: this module grants access to the state and custom
# roles, but the sub-account module is what CREATES them in each account.
# Without it, the grants point at roles that never exist and workflows fail at
# runtime on the second AssumeRole hop.

locals {
  sub_account_config = {
    state = { account_id = "222222222222", region = "us-east-1" }
    dns   = { account_id = "444444444444", region = "us-east-1" }
  }
}

provider "aws" {
  region = "us-east-1"
}

# One provider instance per account the sub-account module manages.
provider "aws" {
  alias    = "sub_account"
  for_each = local.sub_account_config
  region   = each.value.region
  assume_role {
    role_arn = "arn:aws:iam::${each.value.account_id}:role/OrganizationAccountAccessRole"
  }
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

      # Pre-existing roles this repo may assume — the role (and therefore the
      # permissions) can differ per account. Nothing is created here.
      assume_existing_roles = {
        workloads-prod    = "OrganizationAccountAccessRole" # full admin in prod
        workloads-staging = "StagingDeployRole"             # narrower, pre-existing
      }
    },
  ]

  account_ids = {
    state             = "222222222222"
    workloads-prod    = "111111111111"
    workloads-staging = "333333333333"
    dns               = "444444444444"
  }

  # Purpose-built roles this module pair CREATES and grants. platform-app can
  # only touch Route53 in the dns account.
  custom_roles = {
    dns = {
      Route53Only = {
        policy_arns        = ["arn:aws:iam::aws:policy/AmazonRoute53FullAccess"]
        trusted_oidc_repos = ["platform-app"]
      }
    }
  }
}

# Creates the state role (state account) and the Route53 role (dns account).
# workloads-prod / workloads-staging need no instance here — their roles
# already exist and are only referenced.
module "github_oidc_sub_account" {
  source   = "git::https://github.com/GlueOps/opentofu-module-aws-github-oidc-sub-account.git?ref=v0.0.1"
  for_each = toset(keys(local.sub_account_config))

  providers = { aws = aws.sub_account[each.key] }

  repos        = module.github_oidc.sub_account_inputs[each.key].repos
  custom_roles = module.github_oidc.sub_account_inputs[each.key].custom_roles
}

# Everything platform-app's workflow needs — including every downstream role
# ARN it may assume, grouped by kind:
#   role_to_assume, state_role_arn, state_prefix,
#   existing_role_arns  = { workloads-prod = "...", workloads-staging = "..." }
#   custom_role_arns = { "dns--Route53Only" = "..." }
output "platform_app_workflow" {
  value = module.github_oidc.workflow_config["platform-app"]
}
