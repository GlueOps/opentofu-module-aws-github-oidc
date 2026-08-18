mock_provider "aws" {}

run "rejects_non_numeric_ids" {
  command = plan

  variables {
    github_repos = {
      "demo-app" = {
        github_org     = "Example-Org"
        github_org_id  = "1234567"
        repo_id        = "R_kgDOG1234" # GraphQL node ID, not the REST numeric id
        policy_arns    = []
        state_account  = "state"
        infra_accounts = {}
      }
    }
    sub_account_ids = { state = "222222222222" }
  }

  expect_failures = [var.github_repos]
}

run "rejects_unknown_state_account" {
  command = plan

  variables {
    github_repos = {
      "demo-app" = {
        github_org     = "Example-Org"
        github_org_id  = "1234567"
        repo_id        = "9876543"
        policy_arns    = []
        state_account  = "no-such-account"
        infra_accounts = {}
      }
    }
    sub_account_ids = { state = "222222222222" }
  }

  expect_failures = [aws_iam_role_policy.github_oidc_assume_roles]
}

run "rejects_unknown_infra_account" {
  command = plan

  variables {
    github_repos = {
      "demo-app" = {
        github_org     = "Example-Org"
        github_org_id  = "1234567"
        repo_id        = "9876543"
        policy_arns    = []
        state_account  = "state"
        infra_accounts = { "no-such-account" = "DeployRole" }
      }
    }
    sub_account_ids = { state = "222222222222" }
  }

  expect_failures = [aws_iam_role_policy.github_oidc_assume_roles]
}
