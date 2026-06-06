# ============================================================================
# AWS SAM Template Parsing Tests
# ============================================================================
#
# Tests that valid SAM templates are parsed and translated correctly.
# Requires LocalStack (make localstack-start) or real AWS credentials.

mock_provider "aws" {}

run "sam_simple_parses_without_errors" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-simple.yaml"
    config_format = "sam"
  }

  assert {
    condition     = length(local.validation_errors) == 0
    error_message = "Expected no validation errors for simple SAM template, got: ${join(", ", local.validation_errors)}"
  }

  assert {
    # SAM has no service field; the Description is deliberately NOT used (too long
    # for the 64-char IAM role-name limit). With no Metadata.ServiceName present in
    # this fixture, the service falls back to the stable "sam-service".
    condition     = local.parsed_config.service == "sam-service"
    error_message = "Expected fallback service name 'sam-service', got: ${local.parsed_config.service}"
  }

  assert {
    condition     = local.parsed_config.provider.name == "aws"
    error_message = "Expected provider.name to be 'aws'"
  }

  assert {
    condition     = contains(keys(local.parsed_config.functions), "HelloFunction")
    error_message = "Expected HelloFunction in translated functions"
  }

  assert {
    condition     = local.parsed_config.functions["HelloFunction"].handler == "src/index.handler"
    error_message = "Expected handler to be 'src/index.handler'"
  }

  assert {
    condition     = local.parsed_config.functions["HelloFunction"].runtime == "nodejs18.x"
    error_message = "Expected runtime to be 'nodejs18.x'"
  }
}

run "sam_globals_inheritance" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-globals.yaml"
    config_format = "sam"
  }

  assert {
    condition     = length(local.validation_errors) == 0
    error_message = "Expected no validation errors for globals SAM template, got: ${join(", ", local.validation_errors)}"
  }

  assert {
    condition     = local.parsed_config.provider.runtime == "nodejs18.x"
    error_message = "Expected provider runtime from Globals.Function"
  }

  assert {
    condition     = local.parsed_config.functions["WorkerFunction"].runtime == "python3.11"
    error_message = "Expected WorkerFunction to override runtime from Globals"
  }

  assert {
    condition     = local.parsed_config.functions["ApiFunction"].runtime == null
    error_message = "Expected ApiFunction to have null runtime (inherits from provider via Globals)"
  }
}
