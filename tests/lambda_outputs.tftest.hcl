# Lambda Output Tests
# Tests for Lambda function outputs

# Test 1: function_arns map contains all functions
run "function_arns_output_populated" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-minimal.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition     = length(output.function_arns) == length(local.functions_with_defaults)
    error_message = "function_arns output should contain all functions"
  }
}

# Test 2: function_names map contains all functions
run "function_names_output_populated" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-minimal.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition     = length(output.function_names) == length(local.functions_with_defaults)
    error_message = "function_names output should contain all functions"
  }
}

# Test 3: role_arns map contains all roles
run "role_arns_output_populated" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-minimal.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition     = length(output.role_arns) == length(local.functions_with_defaults)
    error_message = "role_arns output should contain all roles"
  }
}

# Test 4: invoke_arns map contains all functions
run "invoke_arns_output_populated" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-minimal.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition     = length(output.function_invoke_arns) == length(local.functions_with_defaults)
    error_message = "function_invoke_arns output should contain all functions"
  }
}

# Test 5: Empty maps when no functions defined
run "functionless_empty_output_maps" {
  command = plan

  variables {
    config_path      = "tests/fixtures/functionless.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition = (
      length(output.function_arns) == 0 &&
      length(output.function_names) == 0 &&
      length(output.role_arns) == 0 &&
      length(output.function_invoke_arns) == 0
    )
    error_message = "All Lambda outputs should be empty maps when no functions are defined"
  }
}
