mock_provider "aws" {}

variables {
  github_org    = { name = "Example-Org", id = "1234567" }
  repo_defaults = { state_account = "state", default_branch = "main" }

  github_repos = [
    { repo_name = "demo-app", repo_id = "9876543" },
  ]

  sub_account_ids = { state = "222222222222" }
}

run "oidc_provider" {
  command = plan

  assert {
    condition     = aws_iam_openid_connect_provider.github.url == "https://token.actions.githubusercontent.com"
    error_message = "OIDC provider must target GitHub.com's Actions token issuer"
  }

  assert {
    condition     = aws_iam_openid_connect_provider.github.client_id_list == toset(["sts.amazonaws.com"])
    error_message = "audience must be sts.amazonaws.com (matched by the trust policies' aud condition)"
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github.thumbprint_list) > 0
    error_message = "thumbprints are vestigial for GitHub but the field must stay populated (provider cannot clear it once set)"
  }
}
