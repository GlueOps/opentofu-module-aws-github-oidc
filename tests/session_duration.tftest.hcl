mock_provider "aws" {}

variables {
  github_org  = { name = "Example-Org", id = "1234567" }
  account_ids = { state = "222222222222" }
}

run "defaults_to_aws_default" {
  command = plan

  variables {
    repo_defaults = { state_account = "state", default_branch = "main" }
    github_repos = [
      { repo_name = "plain-app", repo_id = "9876543" },
    ]
  }

  assert {
    condition     = aws_iam_role.github_oidc["plain-app"].max_session_duration == 3600
    error_message = "max_session_duration must default to 3600 (the AWS default) when unset"
  }
}

run "repo_defaults_apply_and_entry_overrides" {
  command = plan

  variables {
    repo_defaults = {
      state_account        = "state"
      default_branch       = "main"
      max_session_duration = 43200
    }
    github_repos = [
      { repo_name = "long-app", repo_id = "9876543" },
      { repo_name = "short-app", repo_id = "9876544", max_session_duration = 7200 },
    ]
  }

  assert {
    condition     = aws_iam_role.github_oidc["long-app"].max_session_duration == 43200
    error_message = "repo_defaults.max_session_duration must apply when the entry does not set one"
  }

  assert {
    condition     = aws_iam_role.github_oidc["short-app"].max_session_duration == 7200
    error_message = "a per-repo max_session_duration must override repo_defaults"
  }
}

run "rejects_out_of_range_on_entry" {
  command = plan

  variables {
    repo_defaults = { state_account = "state", default_branch = "main" }
    github_repos = [
      { repo_name = "demo-app", repo_id = "9876543", max_session_duration = 1800 },
    ]
  }

  expect_failures = [var.github_repos]
}

run "rejects_out_of_range_on_defaults" {
  command = plan

  variables {
    repo_defaults = {
      state_account        = "state"
      default_branch       = "main"
      max_session_duration = 86400
    }
    github_repos = [
      { repo_name = "demo-app", repo_id = "9876543" },
    ]
  }

  expect_failures = [var.repo_defaults]
}
