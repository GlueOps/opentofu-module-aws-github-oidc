mock_provider "aws" {}

variables {
  github_repos = {
    # Repo with managed policies attached: gets attachments, no inline
    # AssumeRoles policy (current v0 behavior).
    "admin-app" = {
      github_org     = "Example-Org"
      policy_arns    = ["arn:aws:iam::aws:policy/AdministratorAccess", "arn:aws:iam::aws:policy/ReadOnlyAccess"]
      state_account  = "state"
      infra_accounts = {}
    }
    # Repo without managed policies: gets the inline AssumeRoles policy
    # covering its infra accounts and its s3-state role.
    "deploy-app" = {
      github_org     = "Example-Org"
      policy_arns    = []
      state_account  = "state"
      infra_accounts = { core = "OrganizationAccountAccessRole" }
    }
  }

  sub_account_ids = {
    state = "222222222222"
    core  = "111111111111"
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

  # v0 behavior: only repos with zero managed policies get the inline policy.
  # (v1 will grant state-role access unconditionally; update this run then.)
  assert {
    condition     = keys(aws_iam_role_policy.github_oidc_assume_roles) == ["deploy-app"]
    error_message = "inline AssumeRoles policy must exist exactly for repos without managed policies"
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
}
