# S3 Event Validation Tests
# LocalStack Compatibility: FULL
# Tests for validating S3 event configurations
# These are validation tests - test that invalid configs are rejected

mock_provider "aws" {}

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
