# HTTP Event Parsing Tests
# LocalStack Compatibility: FULL
# Tests for extracting and parsing HTTP events from Serverless Framework configuration
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

run "short_form_http_event" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-short-form.yml"
  }

  assert {
    condition     = length(local.http_events) == 1
    error_message = "Should parse one HTTP event from short-form syntax"
  }

  assert {
    condition     = local.http_events[0].http_method == "GET"
    error_message = "Should extract GET method from short-form syntax, got: ${try(local.http_events[0].http_method, "none")}"
  }

  assert {
    condition     = local.http_events[0].http_path == "/users/{id}"
    error_message = "Should extract path correctly from short-form syntax, got: ${try(local.http_events[0].http_path, "none")}"
  }

  assert {
    condition     = local.http_events[0].function_name == "getUser"
    error_message = "Should associate event with correct function"
  }

  assert {
    condition     = local.http_events[0].cors_enabled == false
    error_message = "CORS should be disabled when not specified"
  }
}

run "long_form_http_event" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-long-form.yml"
  }

  assert {
    condition     = length(local.http_events) == 1
    error_message = "Should parse one HTTP event from long-form syntax"
  }

  assert {
    condition     = local.http_events[0].http_method == "POST"
    error_message = "Should extract POST method from long-form syntax"
  }

  assert {
    condition     = local.http_events[0].http_path == "/users"
    error_message = "Should extract path from long-form syntax"
  }

  assert {
    condition     = local.http_events[0].cors_enabled == true
    error_message = "Should detect CORS enabled from long-form syntax"
  }

  assert {
    condition     = local.http_events[0].cors_config == null
    error_message = "Should set cors_config to null when cors: true (use defaults)"
  }
}

run "invalid_http_method" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-invalid-method.yml"
  }

  expect_failures = [
    null_resource.config_validation
  ]
}

run "invalid_http_path" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-invalid-path.yml"
  }

  expect_failures = [
    null_resource.config_validation
  ]
}

run "functions_with_http_events_deduplication" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-short-form.yml"
  }

  assert {
    condition     = length(local.functions_with_http_events) == 1
    error_message = "Should identify one function with HTTP events"
  }

  assert {
    condition     = contains(local.functions_with_http_events, "getUser")
    error_message = "Should include getUser in functions with HTTP events"
  }
}
