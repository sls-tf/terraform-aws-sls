# Test: SQS Queue Resource Translation
# LocalStack Compatibility: FULL
# Validates translation of CloudFormation SQS queues to Terraform aws_sqs_queue resources

mock_provider "aws" {}

run "sqs_queue_resources_created" {
  command = plan

  variables {
    config_path = "tests/fixtures/custom-resources-sqs.yml"
  }

  # Verify SQS queue resources are created
  assert {
    condition     = length(aws_sqs_queue.custom) == 2
    error_message = "Expected 2 SQS queue resources, got ${length(aws_sqs_queue.custom)}"
  }

  # Verify TaskQueue resource exists
  assert {
    condition     = contains(keys(aws_sqs_queue.custom), "TaskQueue")
    error_message = "TaskQueue resource not created"
  }

  # Verify FifoQueue resource exists
  assert {
    condition     = contains(keys(aws_sqs_queue.custom), "FifoQueue")
    error_message = "FifoQueue resource not created"
  }
}

run "sqs_queue_properties_translated" {
  command = plan

  variables {
    config_path = "tests/fixtures/custom-resources-sqs.yml"
  }

  # Verify TaskQueue name
  assert {
    condition     = aws_sqs_queue.custom["TaskQueue"].name == "task-queue-prod"
    error_message = "TaskQueue name not translated correctly"
  }

  # Verify TaskQueue delay
  assert {
    condition     = aws_sqs_queue.custom["TaskQueue"].delay_seconds == 5
    error_message = "TaskQueue delay_seconds not translated correctly"
  }

  # Verify TaskQueue visibility timeout
  assert {
    condition     = aws_sqs_queue.custom["TaskQueue"].visibility_timeout_seconds == 300
    error_message = "TaskQueue visibility_timeout_seconds not translated correctly"
  }

  # Verify TaskQueue message retention
  assert {
    condition     = aws_sqs_queue.custom["TaskQueue"].message_retention_seconds == 1209600
    error_message = "TaskQueue message_retention_seconds not translated correctly"
  }

  # Verify FifoQueue FIFO configuration
  assert {
    condition     = aws_sqs_queue.custom["FifoQueue"].fifo_queue == true
    error_message = "FifoQueue fifo_queue not translated correctly"
  }

  # Verify FifoQueue content-based deduplication
  assert {
    condition     = aws_sqs_queue.custom["FifoQueue"].content_based_deduplication == true
    error_message = "FifoQueue content_based_deduplication not translated correctly"
  }
}

run "sqs_queue_tags" {
  command = plan

  variables {
    config_path = "tests/fixtures/custom-resources-sqs.yml"
  }

  # Verify tags are added
  assert {
    condition     = aws_sqs_queue.custom["TaskQueue"].tags["Name"] == "TaskQueue"
    error_message = "TaskQueue Name tag not set correctly"
  }

  assert {
    condition     = aws_sqs_queue.custom["TaskQueue"].tags["ManagedBy"] == "sls.tf"
    error_message = "TaskQueue ManagedBy tag not set correctly"
  }

  assert {
    condition     = aws_sqs_queue.custom["TaskQueue"].tags["LogicalId"] == "TaskQueue"
    error_message = "TaskQueue LogicalId tag not set correctly"
  }
}
