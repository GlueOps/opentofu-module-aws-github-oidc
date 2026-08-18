mock_provider "aws" {}

variables {
  github_repos = {
    "demo-app" = {
      github_org     = "Example-Org"
      github_org_id  = "1234567"
      repo_id        = "9876543"
      default_branch = "main"
      policy_arns    = []
      state_account  = "state"
      infra_accounts = {}
    }
    # Declared-but-null allowed_subs must behave exactly like omitting it.
    "null-subs-app" = {
      github_org     = "Example-Org"
      github_org_id  = "1234567"
      repo_id        = "9876545"
      default_branch = "main"
      policy_arns    = []
      state_account  = "state"
      infra_accounts = {}
      allowed_subs   = null
    }
    "master-app" = {
      github_org     = "Example-Org"
      github_org_id  = "1234567"
      repo_id        = "9876546"
      policy_arns    = []
      state_account  = "state"
      infra_accounts = {}
      default_branch = "master"
    }
    "pr-app" = {
      github_org          = "Example-Org"
      github_org_id       = "1234567"
      repo_id             = "9876547"
      default_branch      = "main"
      allow_pull_requests = true
      policy_arns         = []
      state_account       = "state"
      infra_accounts      = {}
    }
    "scoped-app" = {
      github_org     = "Example-Org"
      github_org_id  = "1234567"
      repo_id        = "9876544"
      default_branch = "main"
      policy_arns    = []
      state_account  = "state"
      infra_accounts = {}
      allowed_subs   = ["repo:Example-Org@1234567/scoped-app@9876544:ref:refs/heads/main"]
    }
  }

  sub_account_ids = { state = "222222222222" }
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

  # Default scope: the repo's default branch plus pull_request-triggered runs
  # (the ID StringEquals conditions above are the real enforcement).
  assert {
    condition = jsondecode(aws_iam_role.github_oidc["demo-app"].assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"] == [
      "repo:Example-Org@1234567/demo-app@9876543:ref:refs/heads/main",
    ]
    error_message = "default sub pattern must scope to the default branch only (no PR access), immutable format"
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
    error_message = "allowed_subs = null must produce the same default sub patterns as omitting the attribute"
  }
}

run "allowed_subs_override" {
  command = plan

  assert {
    condition = jsondecode(aws_iam_role.github_oidc["scoped-app"].assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"] == [
      "repo:Example-Org@1234567/scoped-app@9876544:ref:refs/heads/main",
    ]
    error_message = "allowed_subs must replace the default sub patterns"
  }

  assert {
    condition     = jsondecode(aws_iam_role.github_oidc["scoped-app"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:repository_id"] == "9876544"
    error_message = "allowed_subs must not disable the ID claim conditions"
  }
}
