# Variable Infrastructure Tests
# Tests for variable input configuration and validation

mock_provider "aws" {}

run "test_default_variable_resolution_settings" {
  command = plan

  variables {
    config_path = "tests/fixtures/simple-function.yml"
  }

  # Default settings should work
  assert {
    condition     = var.strict_variable_resolution == true
    error_message = "strict_variable_resolution should default to true"
  }

  assert {
    condition     = var.max_variable_depth == 10
    error_message = "max_variable_depth should default to 10"
  }

  assert {
    condition     = length(var.environment_vars) == 0
    error_message = "environment_vars should default to empty map"
  }
}

run "test_environment_vars_input" {
  command = plan

  variables {
    config_path = "tests/fixtures/simple-function.yml"
    environment_vars = {
      "NODE_ENV"   = "production"
      "API_KEY"    = "test-key-123"
      "AWS_REGION" = "us-west-2"
    }
  }

  # Should accept environment_vars map
  assert {
    condition     = length(var.environment_vars) == 3
    error_message = "environment_vars should accept map with 3 entries"
  }

  assert {
    condition     = var.environment_vars["NODE_ENV"] == "production"
    error_message = "environment_vars should store NODE_ENV correctly"
  }
}

run "test_strict_variable_resolution_flag" {
  command = plan

  variables {
    config_path                = "tests/fixtures/simple-function.yml"
    strict_variable_resolution = false
  }

  # Should accept false value
  assert {
    condition     = var.strict_variable_resolution == false
    error_message = "strict_variable_resolution should accept false"
  }
}

run "test_max_variable_depth_valid_range" {
  command = plan

  variables {
    config_path        = "tests/fixtures/simple-function.yml"
    max_variable_depth = 5
  }

  # Should accept valid depth
  assert {
    condition     = var.max_variable_depth == 5
    error_message = "max_variable_depth should accept value 5"
  }
}

run "test_max_variable_depth_validation_too_low" {
  command = plan

  variables {
    config_path        = "tests/fixtures/simple-function.yml"
    max_variable_depth = 0
  }

  # Should fail validation for depth = 0
  expect_failures = [
    var.max_variable_depth
  ]
}

run "test_max_variable_depth_validation_too_high" {
  command = plan

  variables {
    config_path        = "tests/fixtures/simple-function.yml"
    max_variable_depth = 51
  }

  # Should fail validation for depth > 50
  expect_failures = [
    var.max_variable_depth
  ]
}
