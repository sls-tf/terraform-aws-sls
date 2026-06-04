# API Gateway Method Key Uniqueness Tests
#
# Regression coverage for the duplicate-key bug recorded in
# docs/snapshot-review-2026-06-04-3cca7f5d.md: aws_api_gateway_method.endpoints
# and aws_api_gateway_integration.lambda keyed their for_each by
# "${function_name}_${method}", omitting the path. A single function serving two
# paths under the same method (GET /alpha and GET /beta) produced two identical
# keys and Terraform failed plan with "Two different items produced the key".
# The key now includes the path, so each (function, method, path) is distinct.
#
# Pure plan-time for_each logic, so a mock AWS provider suffices — no LocalStack
# or AWS credentials required.

mock_provider "aws" {}

run "same_function_same_method_distinct_paths" {
  command = plan

  variables {
    config_path      = "tests/fixtures/http-same-function-multi-path.yml"
    lambda_code_path = "tests/fixtures"
  }

  # Two HTTP events ⇒ two methods and two integrations, not one collapsed entry.
  assert {
    condition     = length(aws_api_gateway_method.endpoints) == 2
    error_message = "Two same-method/different-path events on one function should yield two API Gateway methods"
  }

  assert {
    condition     = length(aws_api_gateway_integration.lambda) == 2
    error_message = "Two same-method/different-path events on one function should yield two integrations"
  }

  # Both paths must be represented in the (plan-known) for_each keys.
  assert {
    condition = (
      anytrue([for k in keys(aws_api_gateway_method.endpoints) : can(regex("/alpha$", k))]) &&
      anytrue([for k in keys(aws_api_gateway_method.endpoints) : can(regex("/beta$", k))])
    )
    error_message = "Method keys should distinguish the two paths (/alpha and /beta)"
  }
}

# A function with the same path under two different methods must also stay
# distinct (guards against a path-only key regressing in the other direction).
run "same_path_distinct_methods" {
  command = plan

  variables {
    config_path      = "tests/fixtures/http-multiple-methods.yml"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition     = length(aws_api_gateway_method.endpoints) == 2
    error_message = "GET and POST on /users should yield two distinct methods"
  }
}
