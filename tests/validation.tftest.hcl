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

run "rejects_unknown_trusted_repo" {
  command = plan

  variables {
    github_repos = {
      "demo-app" = {
        github_org     = "Example-Org"
        github_org_id  = "1234567"
        repo_id        = "9876543"
        policy_arns    = []
        state_account  = "state"
        infra_accounts = {}
      }
    }
    sub_account_ids = { state = "222222222222" }
    custom_sub_account_roles = {
      "state--Whatever" = {
        account            = "state"
        policy_arns        = []
        inline_policy      = null
        trusted_oidc_repos = ["no-such-repo"]
      }
    }
  }

  expect_failures = [aws_iam_openid_connect_provider.github]
}

run "rejects_custom_role_with_unknown_account" {
  command = plan

  variables {
    github_repos = {
      "demo-app" = {
        github_org     = "Example-Org"
        github_org_id  = "1234567"
        repo_id        = "9876543"
        policy_arns    = []
        state_account  = "state"
        infra_accounts = {}
      }
    }
    sub_account_ids = { state = "222222222222" }
    custom_sub_account_roles = {
      "ghost--Whatever" = {
        account            = "no-such-account"
        policy_arns        = []
        inline_policy      = null
        trusted_oidc_repos = ["demo-app"]
      }
    }
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
