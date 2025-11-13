# API Gateway Deployment and Stage Tests
# LocalStack Compatibility: FULL
# Tests for deployment, stage creation, and outputs
# These tests validate deployment and stage configuration

provider "aws" {
  region = "us-east-1"

  # Skip AWS-specific validations when using LocalStack
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack

  # CRITICAL: LocalStack requires S3 path-style access
  s3_use_path_style = var.use_localstack

  # Dynamic endpoints - only populated when use_localstack = true
  dynamic "endpoints" {
    for_each = var.use_localstack ? [1] : []
    content {
      apigateway = var.localstack_endpoint
      dynamodb   = var.localstack_endpoint
      events     = var.localstack_endpoint
      iam        = var.localstack_endpoint
      lambda     = var.localstack_endpoint
      route53    = var.localstack_endpoint
      s3         = var.localstack_endpoint
      sns        = var.localstack_endpoint
      sqs        = var.localstack_endpoint
      sts        = var.localstack_endpoint
    }
  }
}

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
