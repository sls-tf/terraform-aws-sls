# Event Source Validation Tests
# Tests for DynamoDB Stream and SQS event configuration validation

mock_provider "aws" {}

run "test_dynamodb_invalid_batch_size" {
  command = plan

  variables {
    config_path   = "tests/fixtures/dynamodb-invalid-batch-size.yml"
    config_format = "yaml"
  }

  # Verify plan fails due to invalid batch size
  expect_failures = [
    null_resource.config_validation
  ]
}

run "test_sqs_invalid_batch_size" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sqs-invalid-batch-size.yml"
    config_format = "yaml"
  }

  # Verify plan fails due to invalid batch size for standard queue
  expect_failures = [
    null_resource.config_validation
  ]
}

run "test_invalid_starting_position" {
  command = plan

  variables {
    config_path   = "tests/fixtures/invalid-starting-position.yml"
    config_format = "yaml"
  }

  # Verify plan fails due to invalid starting position
  expect_failures = [
    null_resource.config_validation
  ]
}

run "test_invalid_arn_format" {
  command = plan

  variables {
    config_path   = "tests/fixtures/invalid-arn-format.yml"
    config_format = "yaml"
  }

  # Verify plan fails due to invalid ARN format
  expect_failures = [
    null_resource.config_validation
  ]
}

run "test_valid_configuration_passes" {
  command = plan

  variables {
    config_path   = "tests/fixtures/dynamodb-stream-basic.yml"
    config_format = "yaml"
  }

  # Verify valid configuration passes all validations
  assert {
    condition     = length(local.validation_errors) == 0
    error_message = "Expected no validation errors for valid configuration"
  }
}

run "test_fifo_queue_larger_batch_size_valid" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sqs-fifo-queue.yml"
    config_format = "yaml"
  }

  # Verify FIFO queue allows larger batch sizes (up to 10000)
  assert {
    condition     = length(local.validation_errors) == 0
    error_message = "Expected no validation errors for FIFO queue with batch size 100"
  }
}
