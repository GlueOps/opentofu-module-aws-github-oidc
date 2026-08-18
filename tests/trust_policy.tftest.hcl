mock_provider "aws" {}

variables {
  github_org = { name = "Example-Org", id = "1234567" }

  repo_defaults = {
    state_account  = "state"
    default_branch = "main"
  }

  github_repos = [
    {
      repo_name = "demo-app"
      repo_id   = "9876543"
    },
    # Declared-but-null override_subs must behave exactly like omitting it.
    {
      repo_name     = "null-subs-app"
      repo_id       = "9876545"
      override_subs = null
    },
    {
      repo_name      = "master-app"
      repo_id        = "9876546"
      default_branch = "master"
    },
    {
      repo_name           = "pr-app"
      repo_id             = "9876547"
      allow_pull_requests = true
    },
    {
      repo_name     = "scoped-app"
      repo_id       = "9876544"
      override_subs = ["repo:Example-Org@1234567/scoped-app@9876544:ref:refs/heads/main"]
    },
    # Per-repo org override (multi-org support).
    {
      repo_name     = "other-org-app"
      repo_id       = "9876548"
      github_org    = "Other-Org"
      github_org_id = "7654321"
    },
  ]

  account_ids = { state = "222222222222" }
}

run "id_claim_conditions" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role.github_oidc["demo-app"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    error_message = "trust policy must pin the audience to sts.amazonaws.com"
  }

  assert {
    condition     = jsondecode(aws_iam_role.github_oidc["demo-app"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:repository_owner_id"] == "1234567"
    error_message = "trust policy must pin the immutable numeric owner ID"
  }

  assert {
    condition     = jsondecode(aws_iam_role.github_oidc["demo-app"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:repository_id"] == "9876543"
    error_message = "trust policy must pin the immutable numeric repository ID"
  }

  assert {
    condition     = jsondecode(aws_iam_role.github_oidc["demo-app"].assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity"
    error_message = "trust policy must allow AssumeRoleWithWebIdentity only"
  }

  assert {
    condition     = can(jsondecode(aws_iam_role.github_oidc["demo-app"].assume_role_policy).Statement[0].Principal.Federated)
    error_message = "trust policy principal must be the federated OIDC provider"
    # NOTE: never assert the Principal.Federated VALUE — mock providers
    # generate a placeholder that is not ARN-shaped.
  }

  assert {
    condition     = length(jsondecode(aws_iam_role.github_oidc["demo-app"].assume_role_policy).Statement) == 1
    error_message = "trust policy must contain exactly one statement"
  }
}

run "default_sub_patterns" {
  command = plan

  # Default scope: the repo's default branch only, immutable format
  # (the ID StringEquals conditions above are the real enforcement).
  assert {
    condition = jsondecode(aws_iam_role.github_oidc["demo-app"].assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"] == [
      "repo:Example-Org@1234567/demo-app@9876543:ref:refs/heads/main",
    ]
    error_message = "default sub pattern must scope to the default branch only (no PR access), immutable format"
  }

  assert {
    condition     = tolist(output.expected_subs["demo-app"]) == tolist(["repo:Example-Org@1234567/demo-app@9876543:ref:refs/heads/main"])
    error_message = "expected_subs must surface the exact sub patterns the trust policy accepts"
  }
}

run "pull_request_opt_in" {
  command = plan

  assert {
    condition = jsondecode(aws_iam_role.github_oidc["pr-app"].assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"] == [
      "repo:Example-Org@1234567/pr-app@9876547:ref:refs/heads/main",
      "repo:Example-Org@1234567/pr-app@9876547:pull_request",
    ]
    error_message = "allow_pull_requests = true must add the pull_request sub pattern"
  }
}

run "default_branch_override" {
  command = plan

  assert {
    condition = jsondecode(aws_iam_role.github_oidc["master-app"].assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"] == [
      "repo:Example-Org@1234567/master-app@9876546:ref:refs/heads/master",
    ]
    error_message = "default_branch must change the branch ref in the default sub patterns"
  }
}

run "org_override" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role.github_oidc["other-org-app"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:repository_owner_id"] == "7654321"
    error_message = "per-repo github_org_id must override the module-level github_org"
  }

  assert {
    condition = jsondecode(aws_iam_role.github_oidc["other-org-app"].assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"] == [
      "repo:Other-Org@7654321/other-org-app@9876548:ref:refs/heads/main",
    ]
    error_message = "per-repo org override must flow into the sub patterns"
  }
}

run "legacy_sub_pattern_opt_in" {
  command = plan

  variables {
    immutable_subs_only = false
  }

  assert {
    condition = jsondecode(aws_iam_role.github_oidc["demo-app"].assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"] == [
      "repo:Example-Org/demo-app:ref:refs/heads/main",
      "repo:Example-Org@1234567/demo-app@9876543:ref:refs/heads/main",
    ]
    error_message = "with immutable_subs_only = false the legacy-format equivalents must be included too"
  }
}

run "explicit_null_allowed_subs" {
  command = plan

  assert {
    condition = jsondecode(aws_iam_role.github_oidc["null-subs-app"].assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"] == [
      "repo:Example-Org@1234567/null-subs-app@9876545:ref:refs/heads/main",
    ]
    error_message = "override_subs = null must produce the same default sub patterns as omitting the attribute"
  }
}

run "allowed_subs_override" {
  command = plan

  assert {
    condition = jsondecode(aws_iam_role.github_oidc["scoped-app"].assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"] == [
      "repo:Example-Org@1234567/scoped-app@9876544:ref:refs/heads/main",
    ]
    error_message = "override_subs must replace the default sub patterns"
  }

  assert {
    condition     = jsondecode(aws_iam_role.github_oidc["scoped-app"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:repository_id"] == "9876544"
    error_message = "override_subs must not disable the ID claim conditions"
  }
}
