# Schema Validation Tests
# These tests verify comprehensive validation logic and error collection

provider "null" {}

# Test 1: Missing required field - service
run "missing_service_field" {
  command = plan

  variables {
    config_path = "tests/fixtures/missing-service.yml"
  }

  expect_failures = [
    null_resource.config_validation
  ]
}

# Test 2: Missing required field - provider
run "missing_provider_field" {
  command = plan

  variables {
    config_path = "tests/fixtures/missing-provider.yml"
  }

  expect_failures = [
    null_resource.config_validation
  ]
}

# Test 3: Invalid provider.name (not "aws")
run "invalid_provider_name" {
  command = plan

  variables {
    config_path = "tests/fixtures/invalid-provider-name.yml"
  }

  expect_failures = [
    null_resource.config_validation
  ]
}

# Test 4: Missing runtime at both provider and function levels
run "missing_runtime_strict" {
  command = plan

  variables {
    config_path = "tests/fixtures/missing-runtime.yml"
  }

  expect_failures = [
    null_resource.config_validation
  ]
}

# Test 5: Multiple validation errors collected together
run "multiple_validation_errors" {
  command = plan

  variables {
    config_path = "tests/fixtures/multiple-errors.yml"
  }

  expect_failures = [
    null_resource.config_validation
  ]
}

# Test 6: Functionless configuration acceptance
run "functionless_config_valid" {
  command = plan

  variables {
    config_path = "tests/fixtures/functionless.yml"
  }

  assert {
    condition     = length(local.validation_errors) == 0
    error_message = "Functionless configuration should be valid"
  }
}
