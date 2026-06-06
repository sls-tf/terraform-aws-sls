# HTTP Event Parsing Tests
# LocalStack Compatibility: FULL
# Tests for extracting and parsing HTTP events from Serverless Framework configuration
# These are parsing tests that validate locals - no AWS resources are created

mock_provider "aws" {}

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

  # cors: true uses defaults: cors_config is a map (kept map-typed for type
  # consistency) with null origin/headers rather than a null value.
  assert {
    condition     = local.http_events[0].cors_config.origin == null && local.http_events[0].cors_config.headers == null
    error_message = "Should use default cors_config (null origin/headers) when cors: true"
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
