# S3 Event Parsing Tests
# LocalStack Compatibility: FULL
# Tests for parsing S3 event configurations from serverless.yml
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

run "test_s3_shorthand_syntax_parsing" {
  command = plan

  variables {
    config_path   = "tests/fixtures/s3-shorthand.yml"
    config_format = "yaml"
  }

  # Test that shorthand syntax is parsed and extracted correctly
  assert {
    condition     = length([for evt in local.s3_events_raw : evt if evt != null]) == 1
    error_message = "Expected 1 S3 event to be extracted from shorthand syntax"
  }

  assert {
    condition     = length(local.s3_events_raw) > 0 && try(local.s3_events_raw[0].function_name, "") == "resize"
    error_message = "Expected S3 event to have function_name = 'resize'"
  }
}

run "test_s3_object_syntax_parsing" {
  command = plan

  variables {
    config_path   = "tests/fixtures/s3-object-syntax.yml"
    config_format = "yaml"
  }

  # Test that full object syntax is parsed correctly
  assert {
    condition     = length([for evt in local.s3_events_raw : evt if evt != null]) == 1
    error_message = "Expected 1 S3 event to be extracted from object syntax"
  }

  assert {
    condition     = length(local.s3_events_raw) > 0 && try(local.s3_events_raw[0].function_name, "") == "processImage"
    error_message = "Expected S3 event to have function_name = 'processImage'"
  }
}

run "test_s3_mixed_syntax_in_same_file" {
  command = plan

  variables {
    config_path   = "tests/fixtures/s3-mixed-events.yml"
    config_format = "yaml"
  }

  # Test that S3 events are extracted from mixed event arrays
  assert {
    condition     = length([for evt in local.s3_events_raw : evt if evt != null]) == 1
    error_message = "Expected 1 S3 event when mixed with HTTP events"
  }

  assert {
    condition     = length([for evt in local.s3_events_raw : evt if evt != null]) > 0 && [for evt in local.s3_events_raw : evt if evt != null][0].function_name == "handler1"
    error_message = "Expected S3 event from handler1, not handler2"
  }
}

run "test_s3_default_event_type_applied" {
  command = plan

  variables {
    config_path   = "tests/fixtures/s3-shorthand.yml"
    config_format = "yaml"
  }

  # Test that default event type is applied for shorthand syntax
  assert {
    condition     = length(local.s3_events_normalized) > 0 && try(local.s3_events_normalized[0].event_type, "") == "s3:ObjectCreated:*"
    error_message = "Expected default event type 's3:ObjectCreated:*' for shorthand syntax"
  }
}

run "test_s3_custom_event_type_preserved" {
  command = plan

  variables {
    config_path   = "tests/fixtures/s3-object-syntax.yml"
    config_format = "yaml"
  }

  # Test that custom event type is preserved
  assert {
    condition     = length(local.s3_events_normalized) > 0 && try(local.s3_events_normalized[0].event_type, "") == "s3:ObjectCreated:Put"
    error_message = "Expected custom event type 's3:ObjectCreated:Put' to be preserved"
  }
}

run "test_functions_without_s3_events_graceful_skip" {
  command = plan

  variables {
    config_path   = "tests/fixtures/s3-mixed-events.yml"
    config_format = "yaml"
  }

  # Test that functions without S3 events don't cause errors
  assert {
    condition     = length([for evt in local.s3_events_raw : evt if evt != null && evt.function_name == "handler2"]) == 0
    error_message = "Expected handler2 to have no S3 events"
  }
}
