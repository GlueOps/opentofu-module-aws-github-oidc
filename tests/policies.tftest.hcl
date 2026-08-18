mock_provider "aws" {}

variables {
  github_org = { name = "Example-Org", id = "1234567" }

  repo_defaults = {
    state_account  = "state"
    default_branch = "main"
  }

  github_repos = [
    # Repo with managed policies attached: gets attachments AND the inline
    # AssumeRoles policy (state access must never depend on policy_arns).
    {
      repo_name   = "admin-app"
      repo_id     = "9876541"
      policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess", "arn:aws:iam::aws:policy/ReadOnlyAccess"]
    },
    # Repo without managed policies: inline policy covers its infra accounts,
    # its s3-state role, and the custom role that trusts it.
    {
      repo_name             = "deploy-app"
      repo_id               = "9876542"
      assume_existing_roles = { core = "OrganizationAccountAccessRole" }
    },
  ]

  account_ids = {
    state = "222222222222"
    core  = "111111111111"
  }

  custom_roles = {
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

run "workflow_config_output" {
  command = plan

  assert {
    condition     = output.workflow_config["deploy-app"].state_role_arn == "arn:aws:iam::222222222222:role/oidc-s3-state-deploy-app"
    error_message = "workflow_config must expose the exact state-role ARN"
  }

  assert {
    condition     = output.workflow_config["deploy-app"].state_prefix == "example-org/deploy-app"
    error_message = "workflow_config must expose the state key prefix"
  }

  assert {
    condition     = output.workflow_config["deploy-app"].existing_role_arns["core"] == "arn:aws:iam::111111111111:role/OrganizationAccountAccessRole"
    error_message = "workflow_config must expose infra role ARNs keyed by account"
  }

  assert {
    condition     = tomap(output.workflow_config["deploy-app"].custom_role_arns) == tomap({ "core--Route53Access" = "arn:aws:iam::111111111111:role/oidc-custom-core--Route53Access" })
    error_message = "workflow_config must expose the custom role ARNs keyed by role, so workflows can pick one by name"
  }
}

run "sub_account_inputs_output" {
  command = plan

  assert {
    condition     = keys(output.sub_account_inputs) == ["core", "state"]
    error_message = "sub_account_inputs must have an entry for every account in account_ids"
  }

  assert {
    condition     = keys(output.sub_account_inputs["state"].repos) == ["admin-app", "deploy-app"]
    error_message = "repos must be grouped under their state_account"
  }

  assert {
    condition     = output.sub_account_inputs["state"].repos["deploy-app"].s3_state_role_name == "oidc-s3-state-deploy-app" && output.sub_account_inputs["state"].repos["deploy-app"].state_prefix == "example-org/deploy-app"
    error_message = "grouped repo entries must carry the computed state role name and prefix"
  }

  assert {
    condition     = keys(output.sub_account_inputs["core"].custom_roles) == ["core--Route53Access"] && length(output.sub_account_inputs["state"].custom_roles) == 0
    error_message = "custom roles must be grouped under their account only"
  }

  assert {
    condition     = keys(output.sub_account_inputs["core"].custom_roles["core--Route53Access"].oidc_role_arns) == ["deploy-app"]
    error_message = "grouped custom roles must carry role ARNs for trusted repos only"
  }

  assert {
    condition     = length(output.sub_account_inputs["core"].repos) == 0
    error_message = "accounts that are no repo's state_account must get an empty repos map"
  }
}
