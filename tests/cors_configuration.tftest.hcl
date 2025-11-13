# CORS Configuration Tests
# LocalStack Compatibility: FULL
# Tests for building CORS configuration for API Gateway resources
# These tests validate CORS header configuration logic

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

run "cors_default_values" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-cors-default.yml"
  }

  assert {
    condition     = local.resource_cors_config["/users"].enabled == true
    error_message = "CORS should be enabled when cors: true"
  }

  assert {
    condition     = local.cors_headers["/users"]["Access-Control-Allow-Origin"] == "'*'"
    error_message = "Should use default origin '*', got: ${try(local.cors_headers["/users"]["Access-Control-Allow-Origin"], "none")}"
  }

  assert {
    condition     = contains(split(",", trimprefix(trimsuffix(local.cors_headers["/users"]["Access-Control-Allow-Headers"], "'"), "'")), "Content-Type")
    error_message = "Should include Content-Type in default headers"
  }

  assert {
    condition     = contains(split(",", trimprefix(trimsuffix(local.cors_headers["/users"]["Access-Control-Allow-Headers"], "'"), "'")), "Authorization")
    error_message = "Should include Authorization in default headers"
  }
}

run "cors_custom_configuration" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-cors-custom.yml"
  }

  assert {
    condition     = local.resource_cors_config["/users"].enabled == true
    error_message = "CORS should be enabled with custom config"
  }

  assert {
    condition     = local.cors_headers["/users"]["Access-Control-Allow-Origin"] == "'https://example.com'"
    error_message = "Should use custom origin, got: ${try(local.cors_headers["/users"]["Access-Control-Allow-Origin"], "none")}"
  }

  assert {
    condition     = local.cors_headers["/users"]["Access-Control-Allow-Headers"] == "'Content-Type,Authorization'"
    error_message = "Should use custom headers, got: ${try(local.cors_headers["/users"]["Access-Control-Allow-Headers"], "none")}"
  }
}

run "cors_disabled" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-short-form.yml"
  }

  assert {
    condition     = local.resource_cors_config["/users/{id}"].enabled == false
    error_message = "CORS should be disabled when not specified"
  }

  assert {
    condition     = !contains(keys(local.cors_headers), "/users/{id}")
    error_message = "Should not include CORS headers for non-CORS resources"
  }
}

run "cors_multiple_methods" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-multiple-methods.yml"
  }

  assert {
    condition     = local.resource_cors_config["/users"].enabled == true
    error_message = "CORS should be enabled"
  }

  assert {
    condition     = length(local.resource_cors_config["/users"].methods) == 2
    error_message = "Should collect 2 methods, got: ${length(local.resource_cors_config["/users"].methods)}"
  }

  assert {
    condition     = contains(local.resource_cors_config["/users"].methods, "GET")
    error_message = "Should include GET method"
  }

  assert {
    condition     = contains(local.resource_cors_config["/users"].methods, "POST")
    error_message = "Should include POST method"
  }

  assert {
    condition     = can(regex("GET", local.cors_headers["/users"]["Access-Control-Allow-Methods"]))
    error_message = "CORS methods header should include GET"
  }

  assert {
    condition     = can(regex("POST", local.cors_headers["/users"]["Access-Control-Allow-Methods"]))
    error_message = "CORS methods header should include POST"
  }

  assert {
    condition     = can(regex("OPTIONS", local.cors_headers["/users"]["Access-Control-Allow-Methods"]))
    error_message = "CORS methods header should include OPTIONS"
  }
}
