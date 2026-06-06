# IAM Statement Parsing Tests
# Tests for parsing and normalizing iamRoleStatements

# Test 1: Provider-level iamRoleStatements parsing
mock_provider "aws" {}

run "provider_level_statements_parsed" {
  command = plan

  variables {
    config_path      = "tests/fixtures/iam-provider-level.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition     = length(local.provider_iam_statements) > 0
    error_message = "Provider-level iamRoleStatements should be parsed"
  }

  assert {
    condition     = length(local.provider_iam_statements) == 2
    error_message = "Should parse both provider-level IAM statements"
  }
}

# Test 2: Function-level iamRoleStatements parsing
run "function_level_statements_parsed" {
  command = plan

  variables {
    config_path      = "tests/fixtures/iam-function-level.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition     = length(local.function_iam_statements) > 0
    error_message = "Function-level iamRoleStatements should be parsed"
  }

  assert {
    condition     = length(keys(local.function_iam_statements)) == 2
    error_message = "Should parse IAM statements for both functions"
  }
}

# Test 3: Action normalization (string to array)
run "action_normalization_string_to_array" {
  command = plan

  variables {
    config_path      = "tests/fixtures/iam-provider-level.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition = alltrue([
      for stmt in local.provider_iam_statements_normalized :
      can(tolist(stmt.Action))
    ])
    error_message = "All Action fields should be normalized to arrays"
  }
}

# Test 4: Resource normalization (string to array)
run "resource_normalization_string_to_array" {
  command = plan

  variables {
    config_path      = "tests/fixtures/iam-provider-level.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition = alltrue([
      for stmt in local.provider_iam_statements_normalized :
      can(tolist(stmt.Resource))
    ])
    error_message = "All Resource fields should be normalized to arrays"
  }
}

# Test 5: Missing iamRoleStatements handling
run "missing_statements_handled_gracefully" {
  command = plan

  variables {
    config_path      = "tests/fixtures/iam-no-statements.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition     = length(local.provider_iam_statements) == 0
    error_message = "Missing provider iamRoleStatements should return empty array"
  }

  assert {
    condition = alltrue([
      for func_name, stmts in local.function_iam_statements :
      length(stmts) == 0
    ])
    error_message = "Missing function iamRoleStatements should return empty arrays"
  }
}
