# API Gateway Integration Tests
# LocalStack Compatibility: FULL
# End-to-end tests verifying complete API Gateway functionality
# These tests validate Lambda integration setup in LocalStack or AWS

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

run "complete_api_gateway_stack" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-full-example.yml"
  }

  # Verify REST API
  assert {
    condition     = length(aws_api_gateway_rest_api.this) == 1
    error_message = "Should create one REST API"
  }

  assert {
    condition     = aws_api_gateway_rest_api.this[0].name == "test-api-service-dev"
    error_message = "REST API should use service-stage naming"
  }

  # Verify resource hierarchy
  assert {
    condition     = length(local.all_api_resources) == 4
    error_message = "Should create 4 API resources (/users, /users/{id}, /users/{userId}, /users/{userId}/posts)"
  }

  # Verify methods (5 HTTP events = 5 methods)
  assert {
    condition     = length(aws_api_gateway_method.endpoints) == 5
    error_message = "Should create 5 methods for 5 HTTP events, got: ${length(aws_api_gateway_method.endpoints)}"
  }

  # Verify integrations
  assert {
    condition     = length(aws_api_gateway_integration.lambda) == 5
    error_message = "Should create 5 Lambda integrations"
  }

  # Verify CORS OPTIONS methods (3 paths with CORS enabled)
  assert {
    condition     = length(aws_api_gateway_method.cors_options) == 2
    error_message = "Should create CORS OPTIONS for 2 paths (/users has both GET and POST with cors), got: ${length(aws_api_gateway_method.cors_options)}"
  }

  # Verify Lambda permissions (5 functions with HTTP events)
  assert {
    condition     = length(aws_lambda_permission.api_gateway) == 5
    error_message = "Should create 5 Lambda permissions for 5 functions with HTTP events"
  }

  # Verify deployment and stage
  assert {
    condition     = length(aws_api_gateway_deployment.this) == 1
    error_message = "Should create deployment"
  }

  assert {
    condition     = length(aws_api_gateway_stage.this) == 1
    error_message = "Should create stage"
  }
}

run "mixed_cors_configuration" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-full-example.yml"
  }

  # /users has both GET (default CORS) and POST (custom CORS)
  assert {
    condition     = local.resource_cors_config["/users"].enabled == true
    error_message = "CORS should be enabled on /users"
  }

  # /users/{id} has PUT with CORS and GET without CORS
  assert {
    condition     = local.resource_cors_config["/users/{id}"].enabled == true
    error_message = "CORS should be enabled on /users/{id} because PUT has cors:true"
  }

  # /users/{userId}/posts has GET without CORS
  assert {
    condition     = local.resource_cors_config["/users/{userId}/posts"].enabled == false
    error_message = "CORS should be disabled on /users/{userId}/posts"
  }
}

run "multiple_methods_same_path" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-full-example.yml"
  }

  # /users has both GET and POST
  assert {
    condition     = length(local.resource_cors_config["/users"].methods) == 2
    error_message = "Should collect 2 methods on /users (GET and POST)"
  }

  assert {
    condition     = contains(local.resource_cors_config["/users"].methods, "GET")
    error_message = "Should include GET in /users methods"
  }

  assert {
    condition     = contains(local.resource_cors_config["/users"].methods, "POST")
    error_message = "Should include POST in /users methods"
  }
}

run "nested_path_resources" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-full-example.yml"
  }

  # Verify nested path /users/{userId}/posts creates all intermediates
  assert {
    condition     = contains(keys(local.all_api_resources), "/users")
    error_message = "Should create intermediate /users resource"
  }

  assert {
    condition     = contains(keys(local.all_api_resources), "/users/{userId}")
    error_message = "Should create intermediate /users/{userId} resource"
  }

  assert {
    condition     = contains(keys(local.all_api_resources), "/users/{userId}/posts")
    error_message = "Should create full /users/{userId}/posts resource"
  }
}

run "no_api_gateway_without_http_events" {
  command = plan

  variables {
    config_path = "tests/fixtures/valid-minimal.yml"
  }

  assert {
    condition     = length(aws_api_gateway_rest_api.this) == 0
    error_message = "Should NOT create API Gateway when no HTTP events exist"
  }

  assert {
    condition     = length(local.all_api_resources) == 0
    error_message = "Should NOT create API resources when no HTTP events"
  }

  assert {
    condition     = length(aws_api_gateway_deployment.this) == 0
    error_message = "Should NOT create deployment when no HTTP events"
  }
}
