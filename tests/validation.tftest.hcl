mock_provider "aws" {}

run "rejects_non_numeric_ids" {
  command = plan

  variables {
    github_org    = { name = "Example-Org", id = "1234567" }
    repo_defaults = { state_account = "state", default_branch = "main" }
    account_ids   = { state = "222222222222" }
    github_repos = [
      # GraphQL node ID, not the REST numeric id
      { repo_name = "demo-app", repo_id = "R_kgDOG1234" },
    ]
  }

  expect_failures = [var.github_repos]
}

run "rejects_duplicate_repo_names" {
  command = plan

  variables {
    github_org    = { name = "Example-Org", id = "1234567" }
    repo_defaults = { state_account = "state", default_branch = "main" }
    account_ids   = { state = "222222222222" }
    github_repos = [
      { repo_name = "demo-app", repo_id = "9876543" },
      { repo_name = "demo-app", repo_id = "9876544" },
    ]
  }

  expect_failures = [var.github_repos]
}

run "rejects_unresolved_org" {
  command = plan

  variables {
    # no module-level github_org, no per-repo override
    repo_defaults = { state_account = "state", default_branch = "main" }
    account_ids   = { state = "222222222222" }
    github_repos = [
      { repo_name = "demo-app", repo_id = "9876543" },
    ]
  }

  expect_failures = [var.github_repos]
}

run "rejects_unresolved_default_branch" {
  command = plan

  variables {
    github_org    = { name = "Example-Org", id = "1234567" }
    repo_defaults = { state_account = "state" }
    account_ids   = { state = "222222222222" }
    github_repos = [
      { repo_name = "demo-app", repo_id = "9876543" },
    ]
  }

  expect_failures = [var.github_repos]
}

run "rejects_unresolved_state_account" {
  command = plan

  variables {
    github_org    = { name = "Example-Org", id = "1234567" }
    repo_defaults = { default_branch = "main" }
    account_ids   = { state = "222222222222" }
    github_repos = [
      { repo_name = "demo-app", repo_id = "9876543" },
    ]
  }

  expect_failures = [var.github_repos]
}

run "rejects_unknown_state_account" {
  command = plan

  variables {
    github_org    = { name = "Example-Org", id = "1234567" }
    repo_defaults = { state_account = "no-such-account", default_branch = "main" }
    account_ids   = { state = "222222222222" }
    github_repos = [
      { repo_name = "demo-app", repo_id = "9876543" },
    ]
  }

  expect_failures = [aws_iam_role_policy.github_oidc_assume_roles]
}

run "rejects_unknown_infra_account" {
  command = plan

  variables {
    github_org    = { name = "Example-Org", id = "1234567" }
    repo_defaults = { state_account = "state", default_branch = "main" }
    account_ids   = { state = "222222222222" }
    github_repos = [
      { repo_name = "demo-app", repo_id = "9876543", assume_existing_roles = { "no-such-account" = "DeployRole" } },
    ]
  }

  expect_failures = [aws_iam_role_policy.github_oidc_assume_roles]
}

run "rejects_unknown_trusted_repo" {
  command = plan

  variables {
    github_org    = { name = "Example-Org", id = "1234567" }
    repo_defaults = { state_account = "state", default_branch = "main" }
    account_ids   = { state = "222222222222" }
    github_repos = [
      { repo_name = "demo-app", repo_id = "9876543" },
    ]
    custom_roles = {
      state = {
        Whatever = {
          policy_arns        = []
          trusted_oidc_repos = ["no-such-repo"]
        }
      }
    }
  }

  expect_failures = [var.custom_roles]
}

run "rejects_custom_role_with_unknown_account" {
  command = plan

  variables {
    github_org    = { name = "Example-Org", id = "1234567" }
    repo_defaults = { state_account = "state", default_branch = "main" }
    account_ids   = { state = "222222222222" }
    github_repos = [
      { repo_name = "demo-app", repo_id = "9876543" },
    ]
    custom_roles = {
      no-such-account = {
        Whatever = {
          policy_arns        = []
          trusted_oidc_repos = ["demo-app"]
        }
      }
    }
  }

  expect_failures = [var.custom_roles]
}

