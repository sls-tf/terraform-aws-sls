# SAM Environment Variable Non-Scalar Guard Tests
#
# Coverage for report.md recommendation #2 ("fail loud on leaked intrinsics").
# After the preprocessor evaluates CloudFormation intrinsics, any environment
# variable value that is not scalar means an unsupported/unresolved intrinsic
# (or a literal list/map) leaked through. The module reports the offending
# function + variable name via the config_validation precondition instead of
# raising an opaque tostring() type error or deploying a meaningless string.
#
# The SAM path shells out to scripts/sam-preprocessor.js via data.external; a
# mock AWS provider covers the aws_caller_identity/aws_region data sources so the
# test runs without LocalStack or AWS credentials (js-yaml must be installed in
# scripts/node_modules, which the module bootstraps on first run).

mock_provider "aws" {}

# A list-valued env var must fail the config_validation precondition (fail loud).
run "nonscalar_env_var_fails_loud" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-nonscalar-env.yaml"
    config_format = "sam"
  }

  expect_failures = [
    null_resource.config_validation,
  ]
}

# Ordinary scalar env vars (string/number/bool) must NOT trip the guard.
run "scalar_env_vars_pass" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-scalar-env.yaml"
    config_format = "sam"
  }

  assert {
    condition     = length(local.sam_env_nonscalar_errors) == 0
    error_message = "Scalar env vars should not be flagged as non-scalar"
  }
}
