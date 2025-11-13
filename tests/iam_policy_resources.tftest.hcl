# IAM Policy Resource Tests
# Tests for aws_iam_role_policy resource creation

# Test 1: Policy resource created for function with statements
run "policy_resource_created_with_statements" {
  command = plan

  variables {
    config_path      = "tests/fixtures/iam-function-level.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition     = length(keys(aws_iam_role_policy.lambda_custom_policy)) == 2
    error_message = "Should create policy resources for both functions with statements"
  }

  assert {
    condition = alltrue([
      for key, policy in aws_iam_role_policy.lambda_custom_policy :
      can(policy.name)
    ])
    error_message = "All policy resources should have names"
  }
}

# Test 2: No policy resource for function without statements
run "no_policy_resource_without_statements" {
  command = plan

  variables {
    config_path      = "tests/fixtures/iam-no-statements.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition     = length(keys(aws_iam_role_policy.lambda_custom_policy)) == 0
    error_message = "Should not create policy resources when no IAM statements defined"
  }
}

# Test 3: Policy document JSON structure
run "policy_document_structure_valid" {
  command = plan

  variables {
    config_path      = "tests/fixtures/iam-provider-level.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition = alltrue([
      for key, policy in aws_iam_role_policy.lambda_custom_policy :
      can(jsondecode(policy.policy))
    ])
    error_message = "Policy documents should be valid JSON"
  }

  assert {
    condition = alltrue([
      for key, policy in aws_iam_role_policy.lambda_custom_policy :
      jsondecode(policy.policy).Version == "2012-10-17"
    ])
    error_message = "All policies should have Version 2012-10-17"
  }

  assert {
    condition = alltrue([
      for key, policy in aws_iam_role_policy.lambda_custom_policy :
      can(jsondecode(policy.policy).Statement)
    ])
    error_message = "All policies should have Statement array"
  }
}

# Test 4: Policy naming convention
run "policy_naming_convention" {
  command = plan

  variables {
    config_path      = "tests/fixtures/iam-function-level.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition = alltrue([
      for key, policy in aws_iam_role_policy.lambda_custom_policy :
      can(regex("^[a-z-]+-dev-[a-z]+-policy$", policy.name))
    ])
    error_message = "Policy names should follow {service}-{stage}-{function}-policy pattern"
  }
}

# Test 5: Policy attachment to correct IAM role
run "policy_attached_to_correct_role" {
  command = plan

  variables {
    config_path      = "tests/fixtures/iam-function-level.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition = alltrue([
      for key, policy in aws_iam_role_policy.lambda_custom_policy :
      policy.role == aws_iam_role.lambda_execution[key].name
    ])
    error_message = "Policies should be attached to correct IAM roles"
  }
}
