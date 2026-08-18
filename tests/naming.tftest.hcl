mock_provider "aws" {}

variables {
  github_repos = {
    # Short name: fits every prefix untruncated.
    "demo-app" = {
      github_org     = "Example-Org"
      policy_arns    = []
      state_account  = "state"
      infra_accounts = { core = "DeployRole" }
    }
    # 65 chars: overflows every prefix -> truncated + 8-hex sha256 suffix.
    "platform-infrastructure-deployment-orchestration-service-monorepo" = {
      github_org     = "Example-Org"
      policy_arns    = []
      state_account  = "state"
      infra_accounts = {}
    }
    # 52 chars: exactly fits the 12-char github-oidc- prefix (64 total) but
    # overflows the 14-char oidc-s3-state- prefix -> only the s3 name truncates.
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" = {
      github_org     = "Example-Org"
      policy_arns    = []
      state_account  = "state"
      infra_accounts = {}
    }
  }

  sub_account_ids = {
    state = "222222222222"
    core  = "111111111111"
  }

  custom_sub_account_roles = {
    "team--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" = {
      account            = "core"
      policy_arns        = []
      inline_policy      = null
      trusted_oidc_repos = []
    }
  }

  tags = { Environment = "test" }
}

run "role_names" {
  command = plan

  assert {
    condition     = output.oidc_role_names["demo-app"] == "github-oidc-demo-app"
    error_message = "short repo name must pass through untruncated"
  }

  assert {
    condition     = output.oidc_role_names["platform-infrastructure-deployment-orchestration-service-monorepo"] == "github-oidc-platform-infrastructure-deployment-orchestr-f98b6e97"
    error_message = "long repo name must truncate to prefix + 43 chars + '-' + first 8 hex of sha256(repo)"
  }

  assert {
    condition     = output.oidc_role_names["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"] == "github-oidc-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    error_message = "a 52-char repo exactly fills 64 chars and must NOT be truncated for the oidc prefix"
  }

  assert {
    condition     = alltrue([for name in values(output.oidc_role_names) : length(name) <= 64])
    error_message = "every generated role name must fit the 64-char IAM limit"
  }

  assert {
    condition     = aws_iam_role.github_oidc["demo-app"].name == "github-oidc-demo-app"
    error_message = "the IAM role resource must use the computed role name"
  }
}

run "s3_state_role_names" {
  command = plan

  assert {
    condition     = output.s3_state_role_names["demo-app"] == "oidc-s3-state-demo-app"
    error_message = "short repo name must pass through untruncated"
  }

  assert {
    condition     = output.s3_state_role_names["platform-infrastructure-deployment-orchestration-service-monorepo"] == "oidc-s3-state-platform-infrastructure-deployment-orches-f98b6e97"
    error_message = "long repo name must truncate to prefix + 41 chars + '-' + first 8 hex of sha256(repo)"
  }

  assert {
    condition     = output.s3_state_role_names["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"] == "oidc-s3-state-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-6c1b3dc7"
    error_message = "a 52-char repo overflows the longer s3-state prefix and must be truncated"
  }

  assert {
    condition     = alltrue([for name in values(output.s3_state_role_names) : length(name) <= 64])
    error_message = "every generated s3-state role name must fit the 64-char IAM limit"
  }
}

run "custom_role_names" {
  command = plan

  assert {
    condition     = output.custom_role_names["team--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"] == "oidc-custom-team--xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx-13555b5f"
    error_message = "long custom role key must truncate to prefix + 43 chars + '-' + first 8 hex of sha256(key)"
  }
}

run "state_prefixes_and_tags" {
  command = plan

  assert {
    condition     = output.state_prefixes["demo-app"] == "example-org/demo-app"
    error_message = "state prefix must be lower(org)/lower(repo)"
  }

  assert {
    condition     = output.tags["demo-app"]["GitHubRepo"] == "Example-Org/demo-app" && output.tags["demo-app"]["ManagedBy"] == "opentofu"
    error_message = "computed tags must include GitHubRepo (original casing) and ManagedBy"
  }

  assert {
    condition     = output.tags["demo-app"]["Environment"] == "test"
    error_message = "caller-supplied tags must be merged into computed tags"
  }
}
