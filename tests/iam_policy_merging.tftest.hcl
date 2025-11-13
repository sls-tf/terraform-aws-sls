# IAM Policy Merging Tests
# Tests for merging provider-level and function-level IAM statements

# Test 1: Provider statements only (applies to all functions)
run "provider_statements_only" {
  command = plan

  variables {
    config_path      = "tests/fixtures/iam-provider-level.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition     = length(local.merged_iam_statements) == 2
    error_message = "Should create merged statements for both functions"
  }

  assert {
    condition = alltrue([
      for func_name, stmts in local.merged_iam_statements :
      length(stmts) == 2 # Both functions get the 2 provider statements
    ])
    error_message = "All functions should have provider-level statements"
  }
}

# Test 2: Function statements only (applies to specific function)
run "function_statements_only" {
  command = plan

  variables {
    config_path      = "tests/fixtures/iam-function-level.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition     = length(local.merged_iam_statements["hello"]) == 1
    error_message = "Hello function should have 1 statement"
  }

  assert {
    condition     = length(local.merged_iam_statements["world"]) == 1
    error_message = "World function should have 1 statement"
  }
}

# Test 3: Combined provider + function statements (merged)
run "combined_provider_and_function_statements" {
  command = plan

  variables {
    config_path      = "tests/fixtures/iam-combined.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition     = length(local.merged_iam_statements["uploader"]) == 2
    error_message = "Uploader should have 1 provider + 1 function statement = 2 total"
  }

  assert {
    condition     = length(local.merged_iam_statements["downloader"]) == 2
    error_message = "Downloader should have 1 provider + 1 function statement = 2 total"
  }
}

# Test 4: No statements (empty merged result)
run "no_statements_empty_merged" {
  command = plan

  variables {
    config_path      = "tests/fixtures/iam-no-statements.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition = alltrue([
      for func_name, stmts in local.merged_iam_statements :
      length(stmts) == 0
    ])
    error_message = "Functions without statements should have empty merged arrays"
  }
}

# Test 5: Statement order preserved (provider first, then function)
run "statement_order_preserved" {
  command = plan

  variables {
    config_path      = "tests/fixtures/iam-combined.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition = (
      # First statement should be provider-level (logs)
      local.merged_iam_statements["uploader"][0].Action[0] == "logs:CreateLogGroup" &&
      # Second statement should be function-level (s3)
      contains(local.merged_iam_statements["uploader"][1].Action, "s3:PutObject")
    )
    error_message = "Provider statements should come before function statements"
  }
}
