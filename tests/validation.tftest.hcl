mock_provider "aws" {}

run "rejects_non_numeric_ids" {
  command = plan

  variables {
    github_org      = { name = "Example-Org", id = "1234567" }
    repo_defaults   = { state_account = "state", default_branch = "main" }
    sub_account_ids = { state = "222222222222" }
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
    github_org      = { name = "Example-Org", id = "1234567" }
    repo_defaults   = { state_account = "state", default_branch = "main" }
    sub_account_ids = { state = "222222222222" }
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
    repo_defaults   = { state_account = "state", default_branch = "main" }
    sub_account_ids = { state = "222222222222" }
    github_repos = [
      { repo_name = "demo-app", repo_id = "9876543" },
    ]
  }

  expect_failures = [var.github_repos]
}

run "rejects_unresolved_default_branch" {
  command = plan

  variables {
    github_org      = { name = "Example-Org", id = "1234567" }
    repo_defaults   = { state_account = "state" }
    sub_account_ids = { state = "222222222222" }
    github_repos = [
      { repo_name = "demo-app", repo_id = "9876543" },
    ]
  }

  expect_failures = [var.github_repos]
}

run "rejects_unresolved_state_account" {
  command = plan

  variables {
    github_org      = { name = "Example-Org", id = "1234567" }
    repo_defaults   = { default_branch = "main" }
    sub_account_ids = { state = "222222222222" }
    github_repos = [
      { repo_name = "demo-app", repo_id = "9876543" },
    ]
  }

  expect_failures = [var.github_repos]
}

run "rejects_unknown_state_account" {
  command = plan

  variables {
    github_org      = { name = "Example-Org", id = "1234567" }
    repo_defaults   = { state_account = "no-such-account", default_branch = "main" }
    sub_account_ids = { state = "222222222222" }
    github_repos = [
      { repo_name = "demo-app", repo_id = "9876543" },
    ]
  }

  expect_failures = [aws_iam_role_policy.github_oidc_assume_roles]
}

run "rejects_unknown_infra_account" {
  command = plan

  variables {
    github_org      = { name = "Example-Org", id = "1234567" }
    repo_defaults   = { state_account = "state", default_branch = "main" }
    sub_account_ids = { state = "222222222222" }
    github_repos = [
      { repo_name = "demo-app", repo_id = "9876543", infra_accounts = { "no-such-account" = "DeployRole" } },
    ]
  }

  expect_failures = [aws_iam_role_policy.github_oidc_assume_roles]
}

run "rejects_unknown_trusted_repo" {
  command = plan

  variables {
    github_org      = { name = "Example-Org", id = "1234567" }
    repo_defaults   = { state_account = "state", default_branch = "main" }
    sub_account_ids = { state = "222222222222" }
    github_repos = [
      { repo_name = "demo-app", repo_id = "9876543" },
    ]
    custom_sub_account_roles = {
      "state--Whatever" = {
        account            = "state"
        policy_arns        = []
        inline_policy      = null
        trusted_oidc_repos = ["no-such-repo"]
      }
    }
  }

  expect_failures = [var.custom_sub_account_roles]
}

run "rejects_custom_role_with_unknown_account" {
  command = plan

  variables {
    github_org      = { name = "Example-Org", id = "1234567" }
    repo_defaults   = { state_account = "state", default_branch = "main" }
    sub_account_ids = { state = "222222222222" }
    github_repos = [
      { repo_name = "demo-app", repo_id = "9876543" },
    ]
    custom_sub_account_roles = {
      "no-such-account--Whatever" = {
        account            = "no-such-account"
        policy_arns        = []
        inline_policy      = null
        trusted_oidc_repos = ["demo-app"]
      }
    }
  }

  expect_failures = [aws_iam_role_policy.github_oidc_assume_roles]
}

run "rejects_custom_role_key_account_mismatch" {
  command = plan

  variables {
    github_org      = { name = "Example-Org", id = "1234567" }
    repo_defaults   = { state_account = "state", default_branch = "main" }
    sub_account_ids = { state = "222222222222", core = "111111111111" }
    github_repos = [
      { repo_name = "demo-app", repo_id = "9876543" },
    ]
    custom_sub_account_roles = {
      # key says "state", account says "core" — role would be NAMED for one
      # account but PLACED in another
      "state--Whatever" = {
        account            = "core"
        policy_arns        = []
        inline_policy      = null
        trusted_oidc_repos = ["demo-app"]
      }
    }
  }

  expect_failures = [var.custom_sub_account_roles]
}
