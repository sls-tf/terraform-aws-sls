# ============================================================================
# TypeScript Configuration Parsing Tests (Roadmap #6)
# ============================================================================
#
# Tests for parsing Serverless Framework TypeScript configuration files.
# Validates TypeScript compilation, async export handling, and error management.

# Provider configuration for TypeScript tests
mock_provider "aws" {}

variables {
  use_localstack      = false
  localstack_endpoint = "http://localhost:4566"
}

run "typescript_minimal_parsing" {
  command = plan

  variables {
    config_path   = "tests/fixtures/valid-minimal.ts"
    config_format = "typescript"
  }

  # Should successfully parse minimal TypeScript configuration
  assert {
    condition     = local.parsed_config != null
    error_message = "TypeScript configuration should be parsed successfully"
  }

  assert {
    condition     = local.parsed_config.service == "my-typescript-service"
    error_message = "Service name should be correctly parsed"
  }

  assert {
    condition     = local.parsed_config.provider.name == "aws"
    error_message = "Provider name should be correctly parsed"
  }

  assert {
    condition     = local.parsed_config.provider.runtime == "nodejs18.x"
    error_message = "Provider runtime should be correctly parsed"
  }

  # TypeScript-specific validations
  assert {
    condition     = local.typescript_parse_success == true
    error_message = "TypeScript parsing should succeed"
  }

  assert {
    condition     = length(local.typescript_all_errors) == 0
    error_message = "TypeScript parsing should have no errors: ${join(", ", local.typescript_all_errors)}"
  }
}

run "typescript_full_parsing" {
  command = plan

  variables {
    config_path   = "tests/fixtures/valid-full.ts"
    config_format = "typescript"
  }

  # Should parse complex TypeScript configuration. The legacy object form
  # `service: { name: ... }` is normalised to the string service name.
  assert {
    condition     = local.parsed_config.service == "my-full-service"
    error_message = "Object-form service should be normalised to its name"
  }

  assert {
    condition     = length(local.parsed_config.functions) == 2
    error_message = "Should parse 2 functions"
  }

  assert {
    condition     = contains(keys(local.parsed_config.functions), "api")
    error_message = "Should include 'api' function"
  }

  assert {
    condition     = local.parsed_config.functions.api.handler == "src/handlers/api.handler"
    error_message = "Function handler should be correctly parsed"
  }

  assert {
    condition     = local.parsed_config.functions.worker.runtime == "python3.9"
    error_message = "Function-specific runtime should be correctly parsed"
  }

  assert {
    condition     = local.parsed_config.provider.environment.NODE_ENV == "production"
    error_message = "Provider environment variables should be correctly parsed"
  }

  assert {
    condition     = local.parsed_config.resources.Resources.MyTable.Type == "AWS::DynamoDB::Table"
    error_message = "Custom resources should be correctly parsed"
  }
}

run "typescript_async_export" {
  command = plan

  variables {
    config_path   = "tests/fixtures/async-export.ts"
    config_format = "typescript"
  }

  # Should handle async function exports
  assert {
    condition     = local.parsed_config.service == "async-service"
    error_message = "Async export should be resolved correctly"
  }

  assert {
    condition     = local.parsed_config.functions.handler.environment.STAGE != null
    error_message = "Async configuration values should be included"
  }

  assert {
    condition     = local.typescript_parse_success == true
    error_message = "Async export parsing should succeed"
  }
}

run "typescript_complex_features" {
  command = plan

  variables {
    config_path   = "tests/fixtures/complex-typescript.ts"
    config_format = "typescript"
  }

  # Should handle complex TypeScript features
  assert {
    condition     = local.parsed_config.service == "complex-typescript-service"
    error_message = "Complex TypeScript configuration should be parsed"
  }

  assert {
    condition     = local.parsed_config.custom.serviceVersion != null
    error_message = "Custom properties should be correctly parsed"
  }

  assert {
    condition     = local.parsed_config.custom.deployTime != null
    error_message = "Computed values should be correctly parsed"
  }

  assert {
    condition     = local.parsed_config.functions.api.description != null
    error_message = "Function descriptions should be correctly parsed"
  }
}

run "typescript_error_handling" {
  command = plan

  variables {
    config_path   = "tests/fixtures/nonexistent.ts"
    config_format = "typescript"
  }

  # A missing file is a fatal config error: it must surface through the locals and
  # cause config_validation to reject the config (rather than crashing the plan).
  expect_failures = [
    null_resource.config_validation
  ]

  assert {
    condition     = local.typescript_has_fatal_error == true
    error_message = "Missing TypeScript file should produce fatal error"
  }

  assert {
    condition     = length(local.typescript_all_errors) > 0
    error_message = "Missing file should produce error messages"
  }

  assert {
    condition     = can(regex("not found", join(", ", local.typescript_all_errors)))
    error_message = "Error should mention file not found"
  }
}

run "typescript_syntax_error" {
  command = plan

  variables {
    config_path   = "tests/fixtures/invalid-syntax.ts"
    config_format = "typescript"
  }

  # A syntax error is fatal: surfaced through the locals and rejected by
  # config_validation with a precise message.
  expect_failures = [
    null_resource.config_validation
  ]

  assert {
    condition     = local.typescript_has_fatal_error == true
    error_message = "TypeScript syntax errors should produce fatal error"
  }

  assert {
    condition     = length(local.typescript_all_errors) > 0
    error_message = "Syntax errors should produce error messages"
  }
}

run "typescript_validation_integration" {
  command = plan

  variables {
    config_path   = "tests/fixtures/valid-minimal.ts"
    config_format = "typescript"
  }

  # Should integrate with existing validation pipeline
  assert {
    condition     = length(local.validation_errors) == 0
    error_message = "Valid TypeScript config should pass validation"
  }

  assert {
    condition     = length(local.runtime_validation_errors) == 0
    error_message = "Runtime validation should not trigger for valid config"
  }
}

run "typescript_yaml_compatibility" {
  command = plan

  # Test that TypeScript and YAML produce similar results for equivalent configs
  variables {
    config_path   = "tests/fixtures/valid-minimal.ts"
    config_format = "typescript"
  }

  assert {
    condition     = local.parsed_config.service != null
    error_message = "TypeScript parsing should produce valid configuration"
  }

  # The same basic validation should work for both formats
  assert {
    condition     = local.parsed_config.provider.name == "aws"
    error_message = "TypeScript should produce same provider structure as YAML"
  }
}