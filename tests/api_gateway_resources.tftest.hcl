# API Gateway Resource Generation Tests
# LocalStack Compatibility: FULL
# Tests for creating API Gateway REST API, resources, methods, and integrations
# These tests create actual API Gateway resources in LocalStack or AWS

mock_provider "aws" {}

run "rest_api_creation" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-short-form.yml"
  }

  assert {
    condition     = length(aws_api_gateway_rest_api.this) == 1
    error_message = "Should create REST API when HTTP events exist"
  }

  assert {
    condition     = aws_api_gateway_rest_api.this[0].name == "test-service-dev"
    error_message = "REST API name should be service-stage format"
  }

  assert {
    condition     = aws_api_gateway_rest_api.this[0].description == "API Gateway for test-service"
    error_message = "REST API should have descriptive message"
  }
}

run "no_api_without_http_events" {
  command = plan

  variables {
    config_path = "tests/fixtures/functionless.yml"
  }

  assert {
    condition     = length(aws_api_gateway_rest_api.this) == 0
    error_message = "Should NOT create REST API when no HTTP events exist"
  }
}

run "resource_hierarchy" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-nested-paths.yml"
  }

  assert {
    condition     = length(local.all_api_resources) == 4
    error_message = "Should create 4 resources for nested path, got: ${length(local.all_api_resources)}"
  }

  assert {
    condition     = contains(keys(local.all_api_resources), "/users")
    error_message = "Should create /users resource"
  }

  assert {
    condition     = contains(keys(local.all_api_resources), "/users/{id}")
    error_message = "Should create /users/{id} resource"
  }

  assert {
    condition     = contains(keys(local.all_api_resources), "/users/{id}/posts")
    error_message = "Should create /users/{id}/posts resource"
  }

  assert {
    condition     = contains(keys(local.all_api_resources), "/users/{id}/posts/{postId}")
    error_message = "Should create full path resource"
  }
}

run "method_creation" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-short-form.yml"
  }

  assert {
    condition     = length(aws_api_gateway_method.endpoints) == 1
    error_message = "Should create one method for one HTTP event"
  }

  # The for_each key includes the path (function_method_path) so a single
  # function can serve several paths under one method without key collisions.
  assert {
    condition     = anytrue([for k in keys(aws_api_gateway_method.endpoints) : startswith(k, "getUser_get_")])
    error_message = "Should create method with function_method_path key"
  }

  assert {
    condition     = one([for m in values(aws_api_gateway_method.endpoints) : m.http_method]) == "GET"
    error_message = "Method should use correct HTTP method"
  }

  assert {
    condition     = one([for m in values(aws_api_gateway_method.endpoints) : m.authorization]) == "NONE"
    error_message = "Method should have no authorization"
  }
}

run "lambda_integration" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-short-form.yml"
  }

  assert {
    condition     = length(aws_api_gateway_integration.lambda) == 1
    error_message = "Should create one Lambda integration"
  }

  assert {
    condition     = one([for i in values(aws_api_gateway_integration.lambda) : i.type]) == "AWS_PROXY"
    error_message = "Integration should use AWS_PROXY type"
  }

  assert {
    condition     = one([for i in values(aws_api_gateway_integration.lambda) : i.integration_http_method]) == "POST"
    error_message = "Lambda integration should use POST method"
  }
}

run "cors_options_method" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-cors-default.yml"
  }

  assert {
    condition     = length(aws_api_gateway_method.cors_options) == 1
    error_message = "Should create OPTIONS method for CORS-enabled path"
  }

  assert {
    condition     = contains(keys(aws_api_gateway_method.cors_options), "/users")
    error_message = "Should create OPTIONS method for /users"
  }

  assert {
    condition     = aws_api_gateway_method.cors_options["/users"].http_method == "OPTIONS"
    error_message = "CORS method should be OPTIONS"
  }
}

run "cors_options_integration" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-cors-default.yml"
  }

  assert {
    condition     = length(aws_api_gateway_integration.cors_options) == 1
    error_message = "Should create CORS integration"
  }

  assert {
    condition     = aws_api_gateway_integration.cors_options["/users"].type == "MOCK"
    error_message = "CORS integration should be MOCK type"
  }

  assert {
    condition     = length(aws_api_gateway_method_response.cors_options_200) == 1
    error_message = "Should create CORS method response"
  }

  assert {
    condition     = length(aws_api_gateway_integration_response.cors_options_200) == 1
    error_message = "Should create CORS integration response"
  }
}

run "lambda_permissions" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-short-form.yml"
  }

  assert {
    condition     = length(aws_lambda_permission.api_gateway) == 1
    error_message = "Should create Lambda permission for function with HTTP events"
  }

  assert {
    condition     = contains(keys(aws_lambda_permission.api_gateway), "getUser")
    error_message = "Should create permission for getUser function"
  }

  assert {
    condition     = aws_lambda_permission.api_gateway["getUser"].action == "lambda:InvokeFunction"
    error_message = "Permission should allow Lambda invocation"
  }

  assert {
    condition     = aws_lambda_permission.api_gateway["getUser"].principal == "apigateway.amazonaws.com"
    error_message = "Permission principal should be API Gateway"
  }
}
