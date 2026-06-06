# Lambda Function Resource Tests
# Tests for aws_lambda_function resource generation

# Test 1: Lambda function created per function definition
mock_provider "aws" {}

run "lambda_function_per_definition" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-minimal.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition     = length(aws_lambda_function.functions) == length(local.functions_with_defaults)
    error_message = "Should create one Lambda function per function definition"
  }
}

# Test 2: Function naming: {service}-{stage}-{function_key}
run "lambda_naming_convention" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-minimal.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition = alltrue([
      for key, fn in aws_lambda_function.functions :
      can(regex("^${local.parsed_config.service}-${local.provider_with_defaults.stage}-${key}$", fn.function_name))
    ])
    error_message = "Lambda function names should follow pattern: {service}-{stage}-{function_key}"
  }
}

# Test 3: Runtime, handler, memory, timeout correctly mapped
run "lambda_properties_mapped" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-minimal.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition = alltrue([
      for key, fn in aws_lambda_function.functions :
      fn.runtime != null &&
      fn.handler != null &&
      fn.memory_size != null &&
      fn.timeout != null
    ])
    error_message = "Lambda functions should have runtime, handler, memory_size, and timeout set"
  }
}

# Test 4: Description mapped when present, null when absent
run "lambda_description_optional" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-minimal.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition = alltrue([
      for key, fn in aws_lambda_function.functions :
      (try(local.functions_with_defaults[key].description, null) != null && fn.description != null) ||
      (try(local.functions_with_defaults[key].description, null) == null)
    ])
    error_message = "Lambda description should be mapped when present in config, or null when absent"
  }
}

# Test 5: Function has source_code_hash for change detection
run "lambda_has_source_code_hash" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-minimal.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition = alltrue([
      for key, fn in aws_lambda_function.functions :
      fn.source_code_hash != null && fn.source_code_hash != ""
    ])
    error_message = "Lambda functions should have source_code_hash for change detection"
  }
}

# Test 6: Function references correct code package
run "lambda_references_code_package" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-minimal.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition = alltrue([
      for key, fn in aws_lambda_function.functions :
      fn.filename != null && can(regex("\\.terraform/lambda-.*\\.zip", fn.filename))
    ])
    error_message = "Lambda functions should reference code packages in .terraform/ directory"
  }
}

# Test 7: Environment block created only when variables exist
run "lambda_environment_conditional" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-full.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition = alltrue([
      for key, fn in aws_lambda_function.functions :
      (try(local.functions_with_defaults[key].environment, null) != null && length(fn.environment) > 0) ||
      (try(local.functions_with_defaults[key].environment, null) == null && length(fn.environment) == 0)
    ])
    error_message = "Lambda environment block should only be present when environment variables are defined"
  }
}

# Test 8: Multiple functions with different configurations
run "multiple_functions_different_configs" {
  command = plan

  variables {
    config_path      = "tests/fixtures/valid-full.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition = length(aws_lambda_function.functions) > 1 && alltrue([
      for i, key1 in keys(aws_lambda_function.functions) : alltrue([
        for j, key2 in keys(aws_lambda_function.functions) :
        i == j || aws_lambda_function.functions[key1].function_name != aws_lambda_function.functions[key2].function_name
      ])
    ])
    error_message = "Each function should have its own unique configuration"
  }
}
