# One repo, many accounts: broad "default" roles in some accounts
# (infra_accounts) and scoped custom roles in others, at the same time.
mock_provider "aws" {}

variables {
  github_org    = { name = "Example-Org", id = "1234567" }
  repo_defaults = { state_account = "state", default_branch = "main" }

  github_repos = [
    {
      repo_name = "platform-app"
      repo_id   = "9876543"
      # Broad, pre-existing roles: a different role name per account.
      infra_accounts = {
        workloads-prod    = "OrganizationAccountAccessRole"
        workloads-staging = "StagingDeployRole"
      }
    },
    { repo_name = "other-app", repo_id = "9876544" },
  ]

  sub_account_ids = {
    state             = "222222222222"
    workloads-prod    = "111111111111"
    workloads-staging = "333333333333"
    dns               = "444444444444"
    data              = "555555555555"
  }

  # Scoped custom roles in two further accounts, both trusting the same repo.
  custom_sub_account_roles = {
    "dns--Route53Only" = {
      account            = "dns"
      policy_arns        = ["arn:aws:iam::aws:policy/AmazonRoute53FullAccess"]
      inline_policy      = null
      trusted_oidc_repos = ["platform-app"]
    }
    "data--SecurityGroupPatch" = {
      account            = "data"
      policy_arns        = []
      inline_policy      = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
      trusted_oidc_repos = ["platform-app", "other-app"]
    }
  }
}

run "one_repo_many_accounts" {
  command = plan

  # The repo's single AssumeRoles policy spans all five accounts.
  assert {
    condition = toset(jsondecode(aws_iam_role_policy.github_oidc_assume_roles["platform-app"].policy).Statement[0].Resource) == toset([
      "arn:aws:iam::111111111111:role/OrganizationAccountAccessRole",
      "arn:aws:iam::333333333333:role/StagingDeployRole",
      "arn:aws:iam::222222222222:role/oidc-s3-state-platform-app",
      "arn:aws:iam::444444444444:role/oidc-custom-dns--Route53Only",
      "arn:aws:iam::555555555555:role/oidc-custom-data--SecurityGroupPatch",
    ])
    error_message = "one repo must be able to assume broad roles in some accounts and scoped custom roles in others, plus its state role"
  }

  # A repo not listed in a custom role's trusted_oidc_repos gets no grant to it.
  assert {
    condition     = !contains(jsondecode(aws_iam_role_policy.github_oidc_assume_roles["other-app"].policy).Statement[0].Resource, "arn:aws:iam::444444444444:role/oidc-custom-dns--Route53Only")
    error_message = "custom-role grants must be limited to trusted repos"
  }

  # workflow_config surfaces every downstream role, grouped by kind.
  assert {
    condition     = keys(output.workflow_config["platform-app"].infra_role_arns) == ["workloads-prod", "workloads-staging"]
    error_message = "workflow_config must list the infra roles per account"
  }

  assert {
    condition     = length(output.workflow_config["platform-app"].custom_role_arns) == 2
    error_message = "workflow_config must list every custom role the repo may assume"
  }

  # sub_account_inputs materializes the custom roles in their own accounts.
  assert {
    condition     = keys(output.sub_account_inputs["dns"].custom_roles) == ["dns--Route53Only"] && keys(output.sub_account_inputs["data"].custom_roles) == ["data--SecurityGroupPatch"]
    error_message = "each custom role must be created in exactly its own account"
  }
}
