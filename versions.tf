terraform {
  # optional() is the real floor. The test suite needs OpenTofu >= 1.8
  # (mock_provider), enforced in CI only — consumers are not constrained by it.
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
