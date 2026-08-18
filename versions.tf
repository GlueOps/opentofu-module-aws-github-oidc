terraform {
  # Floor set by the native `deprecated` variable attribute (OpenTofu 1.11+).
  # This also makes the module OpenTofu-only — Terraform does not support it.
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
