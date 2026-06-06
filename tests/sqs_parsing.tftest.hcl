# Test: SQS Queue Parsing
# LocalStack Compatibility: FULL
# Validates parsing of CloudFormation SQS queue resources from serverless.yml

mock_provider "aws" {}

run "sqs_queue_parsing" {
  command = plan

  variables {
    config_path = "tests/fixtures/custom-resources-sqs.yml"
  }

  # Verify SQS queues are parsed
  assert {
    condition     = length(local.sqs_queues) == 2
    error_message = "Expected 2 SQS queues, got ${length(local.sqs_queues)}"
  }

  # Verify TaskQueue is parsed
  assert {
    condition     = contains(keys(local.sqs_queues), "TaskQueue")
    error_message = "TaskQueue not found in parsed SQS queues"
  }

  # Verify FifoQueue is parsed
  assert {
    condition     = contains(keys(local.sqs_queues), "FifoQueue")
    error_message = "FifoQueue not found in parsed SQS queues"
  }

  # Verify TaskQueue properties
  assert {
    condition     = local.sqs_queues["TaskQueue"].Properties.QueueName == "task-queue-prod"
    error_message = "TaskQueue name not parsed correctly"
  }

  # Verify TaskQueue delay
  assert {
    condition     = local.sqs_queues["TaskQueue"].Properties.DelaySeconds == 5
    error_message = "TaskQueue DelaySeconds not parsed correctly"
  }

  # Verify FifoQueue FIFO configuration
  assert {
    condition     = local.sqs_queues["FifoQueue"].Properties.FifoQueue == true
    error_message = "FifoQueue FifoQueue property not parsed correctly"
  }
}

run "sqs_queue_snake_case_conversion" {
  command = plan

  variables {
    config_path = "tests/fixtures/custom-resources-sqs.yml"
  }

  # Verify snake_case conversion for TaskQueue
  assert {
    condition     = local.to_snake_case["TaskQueue"] == "task_queue"
    error_message = "TaskQueue snake_case conversion failed: got ${local.to_snake_case["TaskQueue"]}"
  }

  # Verify snake_case conversion for FifoQueue
  assert {
    condition     = local.to_snake_case["FifoQueue"] == "fifo_queue"
    error_message = "FifoQueue snake_case conversion failed: got ${local.to_snake_case["FifoQueue"]}"
  }
}
