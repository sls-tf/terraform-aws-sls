# Provider Setup Tests
# Tests for archive provider initialization and lambda_code_path variable

provider "null" {}

# Test 1: Archive provider initialization
run "archive_provider_available" {
  command = plan

  variables {
    config_path = "tests/fixtures/valid-minimal.yml"
  }

  assert {
    condition     = length(local.validation_errors) == 0
    error_message = "Configuration should be valid for valid-minimal.yml"
  }
}

# Test 2: lambda_code_path variable validation - non-empty
run "lambda_code_path_non_empty" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-minimal.yml"
    lambda_code_path = ""
  }

  expect_failures = [
    var.lambda_code_path
  ]
}

# Test 3: lambda_code_path defaults to "." (current directory)
run "lambda_code_path_default" {
  command = plan

  variables {
    config_path = "tests/fixtures/valid-minimal.yml"
  }

  assert {
    condition     = var.lambda_code_path == "."
    error_message = "lambda_code_path should default to current directory (.)"
  }
}

# Test 4: lambda_code_path accepts custom path
run "lambda_code_path_custom" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-minimal.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition     = var.lambda_code_path == "tests/fixtures"
    error_message = "lambda_code_path should accept custom path"
  }
}
