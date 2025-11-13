# S3 Event Validation Tests
# LocalStack Compatibility: FULL
# Tests for validating S3 event configurations
# These are validation tests - test that invalid configs are rejected

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

run "test_invalid_event_type_rejected" {
  command = plan

  variables {
    config_path   = "tests/fixtures/s3-invalid-event-type.yml"
    config_format = "yaml"
  }

  # Verify plan fails due to invalid event type
  expect_failures = [
    null_resource.config_validation
  ]
}

run "test_force_deploy_without_existing_rejected" {
  command = plan

  variables {
    config_path   = "tests/fixtures/s3-force-deploy-invalid.yml"
    config_format = "yaml"
  }

  # Verify plan fails due to forceDeploy without existing
  expect_failures = [
    null_resource.config_validation
  ]
}

run "test_invalid_bucket_naming_rejected" {
  command = plan

  variables {
    config_path   = "tests/fixtures/s3-invalid-bucket-name.yml"
    config_format = "yaml"
  }

  # Verify plan fails due to invalid bucket name
  expect_failures = [
    null_resource.config_validation
  ]
}

run "test_duplicate_event_configurations_rejected" {
  command = plan

  variables {
    config_path   = "tests/fixtures/s3-duplicate-config.yml"
    config_format = "yaml"
  }

  # Verify plan fails due to duplicate configurations
  expect_failures = [
    null_resource.config_validation
  ]
}

run "test_valid_configuration_passes" {
  command = plan

  variables {
    config_path   = "tests/fixtures/s3-object-syntax.yml"
    config_format = "yaml"
  }

  # Verify valid configuration passes all validations
  assert {
    condition     = length(local.validation_errors) == 0
    error_message = "Expected no validation errors for valid configuration, got: ${jsonencode(local.validation_errors)}"
  }
}
