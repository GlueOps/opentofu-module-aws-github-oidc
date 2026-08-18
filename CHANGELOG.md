# Changelog

## [2.0.0](https://github.com/GlueOps/opentofu-module-aws-github-oidc/compare/v1.1.0...v2.0.0) (2026-08-18)


### ⚠ BREAKING CHANGES

* the include_legacy_sub_pattern variable (v1.1.0) is replaced by immutable_subs_only (default true, inverted meaning). By default the trust-policy sub condition now contains only the immutable repo:ORG@ID/* pattern; orgs with repos that still mint legacy-format tokens must set immutable_subs_only = false until those repos opt into immutable subject claims. See MIGRATION.md (v1.x -> v2.0.0).

### Features

* default trust policies to immutable-only sub patterns ([#18](https://github.com/GlueOps/opentofu-module-aws-github-oidc/issues/18)) ([f087e94](https://github.com/GlueOps/opentofu-module-aws-github-oidc/commit/f087e94a6918f9ac15b566943924da57a380170a))

## [1.1.0](https://github.com/GlueOps/opentofu-module-aws-github-oidc/compare/v1.0.0...v1.1.0) (2026-08-18)


### Features

* auto-grant custom sub-account roles and add include_legacy_sub_pattern ([#16](https://github.com/GlueOps/opentofu-module-aws-github-oidc/issues/16)) ([8bc1ed9](https://github.com/GlueOps/opentofu-module-aws-github-oidc/commit/8bc1ed901c3468fa7485adf7b40b0d8a76c822b4))

## [1.0.0](https://github.com/GlueOps/opentofu-module-aws-github-oidc/compare/v0.1.0...v1.0.0) (2026-08-18)


### ⚠ BREAKING CHANGES

* each github_repos entry now requires github_org_id and repo_id (numeric GitHub IDs as strings). Trust policies enforce repository_owner_id + repository_id with StringEquals; the sub condition remains (required by IAM for the GitHub OIDC provider) with an org-scoped default matching both legacy and immutable sub formats, overridable per repo via the new allowed_subs field. The inline AssumeRoles policy is now created for every repo, so attaching managed policies no longer removes state-role access. Applying is an in-place trust-policy update: no role recreation, no downtime. See MIGRATION.md.

### Features

* pin trust policies to immutable GitHub numeric IDs ([#14](https://github.com/GlueOps/opentofu-module-aws-github-oidc/issues/14)) ([011a981](https://github.com/GlueOps/opentofu-module-aws-github-oidc/commit/011a9819a1b36aa1be9736031f9af6da233ee346))

## [0.1.0](https://github.com/GlueOps/opentofu-module-aws-github-oidc/compare/v0.0.1...v0.1.0) (2026-08-18)


### Features

* add tofu test suite, CI workflow, and release-please automation ([#12](https://github.com/GlueOps/opentofu-module-aws-github-oidc/issues/12)) ([7779c76](https://github.com/GlueOps/opentofu-module-aws-github-oidc/commit/7779c76c1eb6262fcd8bd3c3b6e2992d61db0f1e))


### Miscellaneous Chores

* add Apache-2.0 LICENSE ([#11](https://github.com/GlueOps/opentofu-module-aws-github-oidc/issues/11)) ([7b70c11](https://github.com/GlueOps/opentofu-module-aws-github-oidc/commit/7b70c11bded04ea27f1dd906a314b7e7f69a1a9e))
