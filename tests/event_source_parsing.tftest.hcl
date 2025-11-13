# Event Source Parsing Tests
# LocalStack Compatibility: FULL
# Tests for DynamoDB Stream and SQS event detection and flattening
# These are parsing tests that validate locals - no AWS resources are created

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

run "test_dynamodb_stream_detection" {
  command = plan

  variables {
    config_path   = "tests/fixtures/dynamodb-stream-basic.yml"
    config_format = "yaml"
  }

  # Test that DynamoDB stream events are detected
  assert {
    condition     = length(keys(local.event_source_mappings)) == 1
    error_message = "Expected 1 event source mapping for DynamoDB stream"
  }

  assert {
    condition     = length([for k, v in local.event_source_mappings : k if v.type == "stream"]) == 1
    error_message = "Expected event type to be 'stream' for DynamoDB"
  }
}

run "test_sqs_queue_detection" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sqs-queue-basic.yml"
    config_format = "yaml"
  }

  # Test that SQS queue events are detected
  assert {
    condition     = length(keys(local.event_source_mappings)) == 1
    error_message = "Expected 1 event source mapping for SQS queue"
  }

  assert {
    condition     = length([for k, v in local.event_source_mappings : k if v.type == "sqs"]) == 1
    error_message = "Expected event type to be 'sqs'"
  }
}

run "test_fifo_queue_detection" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sqs-fifo-queue.yml"
    config_format = "yaml"
  }

  # Test that FIFO queues are detected by .fifo suffix
  assert {
    condition     = length([for k, v in local.event_source_mappings : k if v.is_fifo_queue == true]) == 1
    error_message = "Expected FIFO queue to be detected by .fifo suffix"
  }
}

run "test_multiple_event_sources_flattening" {
  command = plan

  variables {
    config_path   = "tests/fixtures/multiple-event-sources.yml"
    config_format = "yaml"
  }

  # Test that multiple event sources are flattened correctly
  assert {
    condition     = length(keys(local.event_source_mappings)) == 2
    error_message = "Expected 2 event source mappings (stream + sqs), HTTP should be skipped"
  }

  assert {
    condition     = length([for k, v in local.event_source_mappings : k if v.function_name == "processor"]) == 2
    error_message = "Expected both events to reference 'processor' function"
  }
}

run "test_no_event_sources_graceful_handling" {
  command = plan

  variables {
    config_path   = "tests/fixtures/no-event-sources.yml"
    config_format = "yaml"
  }

  # Test that functions without event sources produce empty map
  assert {
    condition     = length(keys(local.event_source_mappings)) == 0
    error_message = "Expected 0 event source mappings for function with no events"
  }
}

run "test_unique_resource_identifiers" {
  command = plan

  variables {
    config_path   = "tests/fixtures/multiple-event-sources.yml"
    config_format = "yaml"
  }

  # Test that resource identifiers follow pattern: {function}_{type}_{index}
  assert {
    condition     = contains(keys(local.event_source_mappings), "processor_stream_0")
    error_message = "Expected resource identifier 'processor_stream_0' for first event"
  }

  assert {
    condition     = contains(keys(local.event_source_mappings), "processor_sqs_1")
    error_message = "Expected resource identifier 'processor_sqs_1' for second event"
  }
}
