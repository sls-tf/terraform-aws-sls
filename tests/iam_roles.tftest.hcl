# IAM Role Tests
# Tests for IAM execution role creation and policy attachments

# Test 1: One IAM role created per function
run "one_role_per_function" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-minimal.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition     = length(aws_iam_role.lambda_execution) == length(local.functions_with_defaults)
    error_message = "Should create one IAM role per function"
  }
}

# Test 2: Role trust policy allows lambda.amazonaws.com
run "role_trust_policy_correct" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-minimal.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition = alltrue([
      for key, role in aws_iam_role.lambda_execution :
      can(regex("lambda\\.amazonaws\\.com", role.assume_role_policy))
    ])
    error_message = "IAM roles should trust lambda.amazonaws.com service"
  }
}

# Test 3: AWSLambdaBasicExecutionPolicy attached
run "basic_execution_policy_attached" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-minimal.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition = alltrue([
      for key, attachment in aws_iam_role_policy_attachment.lambda_logs :
      attachment.policy_arn == "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionPolicy"
    ])
    error_message = "AWSLambdaBasicExecutionPolicy should be attached to all Lambda execution roles"
  }
}

# Test 4: Role naming convention: {service}-{stage}-{function_key}-role
run "role_naming_convention" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-minimal.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition = alltrue([
      for key, role in aws_iam_role.lambda_execution :
      can(regex("^${local.parsed_config.service}-${local.provider_with_defaults.stage}-${key}-role$", role.name))
    ])
    error_message = "IAM role names should follow pattern: {service}-{stage}-{function_key}-role"
  }
}

# Test 5: Functionless configuration (no roles created)
run "functionless_no_roles" {
  command = plan

  variables {
    config_path      = "tests/fixtures/functionless.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition     = length(aws_iam_role.lambda_execution) == 0
    error_message = "Functionless configuration should create no IAM roles"
  }
}

# Test 6: Multiple functions create multiple roles
run "multiple_functions_multiple_roles" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-full.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition = length(aws_iam_role.lambda_execution) > 1 && alltrue([
      for i, key1 in keys(aws_iam_role.lambda_execution) : alltrue([
        for j, key2 in keys(aws_iam_role.lambda_execution) :
        i == j || aws_iam_role.lambda_execution[key1].name != aws_iam_role.lambda_execution[key2].name
      ])
    ])
    error_message = "Each function should have its own unique IAM role"
  }
}
