# API Gateway Deployment and Stage Tests
# LocalStack Compatibility: FULL
# Tests for deployment, stage creation, and outputs
# These tests validate deployment and stage configuration

mock_provider "aws" {}

run "deployment_creation" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-short-form.yml"
  }

  assert {
    condition     = length(aws_api_gateway_deployment.this) == 1
    error_message = "Should create deployment when HTTP events exist"
  }
}

run "deployment_triggers" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-short-form.yml"
  }

  assert {
    condition     = can(aws_api_gateway_deployment.this[0].triggers.redeployment)
    error_message = "Deployment should have redeployment trigger"
  }
}

run "stage_creation" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-short-form.yml"
  }

  assert {
    condition     = length(aws_api_gateway_stage.this) == 1
    error_message = "Should create stage when HTTP events exist"
  }

  assert {
    condition     = aws_api_gateway_stage.this[0].stage_name == "dev"
    error_message = "Stage name should match provider.stage, got: ${try(aws_api_gateway_stage.this[0].stage_name, "none")}"
  }
}

# Note: API Gateway outputs cannot be tested at plan time
# because they depend on resources not yet created
# Output values are tested in integration tests
