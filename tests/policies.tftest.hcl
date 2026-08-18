mock_provider "aws" {}

variables {
  github_repos = {
    # Repo with managed policies attached: gets attachments, no inline
    # AssumeRoles policy (current v0 behavior).
    "admin-app" = {
      github_org     = "Example-Org"
      github_org_id  = "1234567"
      repo_id        = "9876541"
      policy_arns    = ["arn:aws:iam::aws:policy/AdministratorAccess", "arn:aws:iam::aws:policy/ReadOnlyAccess"]
      state_account  = "state"
      infra_accounts = {}
    }
    # Repo without managed policies: gets the inline AssumeRoles policy
    # covering its infra accounts and its s3-state role.
    "deploy-app" = {
      github_org     = "Example-Org"
      github_org_id  = "1234567"
      repo_id        = "9876542"
      policy_arns    = []
      state_account  = "state"
      infra_accounts = { core = "OrganizationAccountAccessRole" }
    }
  }

  sub_account_ids = {
    state = "222222222222"
    core  = "111111111111"
  }

  custom_sub_account_roles = {
    "core--Route53Access" = {
      account            = "core"
      policy_arns        = []
      inline_policy      = null
      trusted_oidc_repos = ["deploy-app"]
    }
  }
}

run "managed_policy_attachments" {
  command = plan

  assert {
    condition     = aws_iam_role_policy_attachment.github_oidc["admin-app--arn:aws:iam::aws:policy/AdministratorAccess"].policy_arn == "arn:aws:iam::aws:policy/AdministratorAccess"
    error_message = "attachment instances must be keyed '<repo>--<policy_arn>' and attach that policy"
  }

  assert {
    condition     = length(keys(aws_iam_role_policy_attachment.github_oidc)) == 2
    error_message = "exactly one attachment instance per (repo, policy_arn) pair"
  }
}

run "inline_assume_roles_policy" {
  command = plan

  # v1 behavior: EVERY repo gets the inline policy — attaching managed
  # policies must never silently remove state-backend access.
  assert {
    condition     = keys(aws_iam_role_policy.github_oidc_assume_roles) == ["admin-app", "deploy-app"]
    error_message = "inline AssumeRoles policy must exist for every repo, managed policies or not"
  }

  assert {
    condition     = contains(jsondecode(aws_iam_role_policy.github_oidc_assume_roles["admin-app"].policy).Statement[0].Resource, "arn:aws:iam::222222222222:role/oidc-s3-state-admin-app")
    error_message = "repos with managed policies must still get state-role access via the inline policy"
  }

  assert {
    condition     = contains(jsondecode(aws_iam_role_policy.github_oidc_assume_roles["deploy-app"].policy).Statement[0].Resource, "arn:aws:iam::111111111111:role/OrganizationAccountAccessRole")
    error_message = "inline policy must allow assuming each configured infra-account role"
  }

  assert {
    condition     = contains(jsondecode(aws_iam_role_policy.github_oidc_assume_roles["deploy-app"].policy).Statement[0].Resource, "arn:aws:iam::222222222222:role/oidc-s3-state-deploy-app")
    error_message = "inline policy must allow assuming the repo's s3-state role in the state account"
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.github_oidc_assume_roles["deploy-app"].policy).Statement[0].Action == "sts:AssumeRole"
    error_message = "inline policy must grant sts:AssumeRole only"
  }

  assert {
    condition     = contains(jsondecode(aws_iam_role_policy.github_oidc_assume_roles["deploy-app"].policy).Statement[0].Resource, "arn:aws:iam::111111111111:role/oidc-custom-core--Route53Access")
    error_message = "repos listed in a custom role's trusted_oidc_repos must be granted sts:AssumeRole on it"
  }

  assert {
    condition     = !contains(jsondecode(aws_iam_role_policy.github_oidc_assume_roles["admin-app"].policy).Statement[0].Resource, "arn:aws:iam::111111111111:role/oidc-custom-core--Route53Access")
    error_message = "repos NOT listed in trusted_oidc_repos must not be granted the custom role"
  }
}
