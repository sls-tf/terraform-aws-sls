# Test: Lambda naming-convention lint
# functions_with_generated_names output + the brownfield check warning wiring.
# (check-block failures are warnings, so plans still pass; the output carries
# the assertable signal.)

# Region/account feed constructed SNS ARNs (externally-owned topic fallback);
# the provider validates ARN shape, so the mock's random strings must be
# overridden with plausible values.
mock_provider "aws" {
  override_data {
    target = data.aws_region.current
    values = {
      region = "us-east-1"
    }
  }
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }
}

run "generated_names_reported" {
  command = plan

  variables {
    config_path = "tests/fixtures/alarm-sets.yml"
  }

  # Both functions omit name: -> both reported with the generated convention
  assert {
    condition = output.functions_with_generated_names == {
      ingest  = "alarm-sets-dev-ingest"
      process = "alarm-sets-dev-process"
    }
    error_message = "Generated-name report incorrect: ${jsonencode(output.functions_with_generated_names)}"
  }
}

run "explicit_names_not_reported" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-self-httpapi.yaml"
    config_format = "sam"
  }

  # Every function in this fixture sets FunctionName -> nothing to warn about
  assert {
    condition     = length(output.functions_with_generated_names) == 0
    error_message = "Explicitly-named functions must not be reported: ${jsonencode(output.functions_with_generated_names)}"
  }
}

run "lint_warns_not_fails_under_scoped_resource_types" {
  command = plan

  variables {
    config_path    = "tests/fixtures/alarm-sets.yml"
    resource_types = ["AWS::DynamoDB::Table"]
  }

  # terraform test promotes check warnings to failures — expecting the check
  # to fire IS the assertion that the lint triggers under a scoped allowlist.
  expect_failures = [check.lambda_naming_convention]

  # The plan itself must still succeed and resources still materialize.
  assert {
    condition     = length(aws_lambda_function.functions) == 2
    error_message = "Plan should succeed with a naming warning, not fail"
  }
}
