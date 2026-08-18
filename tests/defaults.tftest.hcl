mock_provider "aws" {}

variables {
  github_org = { name = "Example-Org", id = "1234567" }

  repo_defaults = {
    state_account       = "state"
    default_branch      = "main"
    allow_pull_requests = true
  }

  github_repos = [
    # Inherits everything from github_org + repo_defaults.
    { repo_name = "plain-app", repo_id = "9876543" },
    # Overrides every defaultable field.
    {
      repo_name           = "special-app"
      repo_id             = "9876544"
      state_account       = "alt-state"
      default_branch      = "trunk"
      allow_pull_requests = false
    },
  ]

  sub_account_ids = {
    state       = "222222222222"
    "alt-state" = "333333333333"
  }
}

run "defaults_apply" {
  command = plan

  assert {
    condition     = output.workflow_config["plain-app"].state_role_arn == "arn:aws:iam::222222222222:role/oidc-s3-state-plain-app"
    error_message = "repo_defaults.state_account must apply when the entry does not set one"
  }

  assert {
    condition = jsondecode(aws_iam_role.github_oidc["plain-app"].assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"] == [
      "repo:Example-Org@1234567/plain-app@9876543:ref:refs/heads/main",
      "repo:Example-Org@1234567/plain-app@9876543:pull_request",
    ]
    error_message = "repo_defaults default_branch and allow_pull_requests must apply when the entry does not set them"
  }
}

run "per_repo_overrides_win" {
  command = plan

  assert {
    condition     = output.workflow_config["special-app"].state_role_arn == "arn:aws:iam::333333333333:role/oidc-s3-state-special-app"
    error_message = "a per-repo state_account must override repo_defaults"
  }

  assert {
    condition = jsondecode(aws_iam_role.github_oidc["special-app"].assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"] == [
      "repo:Example-Org@1234567/special-app@9876544:ref:refs/heads/trunk",
    ]
    error_message = "per-repo default_branch and allow_pull_requests = false must override repo_defaults"
  }
}
