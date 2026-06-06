# IAM Statement Validation Tests
# Tests for validating IAM statement structure and required fields

# Test 1: Invalid Effect value rejection
mock_provider "aws" {}

run "invalid_effect_value_rejected" {
  command = plan

  variables {
    config_path      = "tests/fixtures/iam-invalid-effect.yml"
    lambda_code_path = "tests/fixtures"
  }

  expect_failures = [
    null_resource.config_validation
  ]
}

# Test 2: Missing Action field rejection
run "missing_action_field_rejected" {
  command = plan

  variables {
    config_path      = "tests/fixtures/iam-missing-action.yml"
    lambda_code_path = "tests/fixtures"
  }

  expect_failures = [
    null_resource.config_validation
  ]
}

# Test 3: Missing Resource field rejection
run "missing_resource_field_rejected" {
  command = plan

  variables {
    config_path      = "tests/fixtures/iam-missing-resource.yml"
    lambda_code_path = "tests/fixtures"
  }

  expect_failures = [
    null_resource.config_validation
  ]
}

# Test 4: Invalid action format rejection (no service:action pattern)
run "invalid_action_format_rejected" {
  command = plan

  variables {
    config_path      = "tests/fixtures/iam-invalid-action-format.yml"
    lambda_code_path = "tests/fixtures"
  }

  expect_failures = [
    null_resource.config_validation
  ]
}

# Test 5: Valid IAM statements pass validation
run "valid_iam_statements_pass" {
  command = plan

  variables {
    config_path      = "tests/fixtures/iam-combined.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition     = length(local.validation_errors) == 0
    error_message = "Valid IAM statements should not produce validation errors"
  }
}
