# ============================================================================
# Shared Test Configuration - LocalStack Compatible
# ============================================================================
#
# LocalStack Compatibility: TEMPLATE
#
# This file provides reusable provider configuration for dual-mode testing.
# Copy the provider block below into your test files to enable testing with
# both LocalStack and real AWS.
#
# USAGE:
# 1. Copy the entire provider block below to your .tftest.hcl file
# 2. Place it before any run blocks
# 3. Run tests with:
#    - LocalStack: terraform test -var="use_localstack=true"
#    - AWS:        terraform test -var="use_localstack=false"
#    - Or use Make: make test-local / make test-aws
#
# COMPATIBILITY LEVELS:
# - FULL:    All tests work with LocalStack Community Edition
# - PARTIAL: Some tests require real AWS (use skip conditions)
# - NONE:    Test file requires real AWS (Pro features, advanced IAM)
#
# SKIP PATTERN:
# For AWS-only tests within a PARTIAL file:
#   run "aws_only_test" {
#     command = plan
#
#     # Skip this test when using LocalStack
#     # condition = !var.use_localstack
#
#     variables { ... }
#     assert { ... }
#   }
#
# Note: Terraform test framework doesn't support conditional test execution
# in the same way. Use conditional assertions instead.
#
# ============================================================================

# AWS Provider Configuration - Dual Mode (LocalStack/AWS)
mock_provider "aws" {}

# ============================================================================
# Test Examples
# ============================================================================

# Example 1: Basic test that works in both modes
# run "example_basic_test" {
#   command = plan
#
#   variables {
#     config_path = "tests/fixtures/basic.yml"
#   }
#
#   assert {
#     condition     = length(aws_lambda_function.functions) > 0
#     error_message = "Expected Lambda functions to be created"
#   }
# }

# Example 2: Test with conditional assertion for LocalStack differences
# run "example_conditional_test" {
#   command = plan
#
#   variables {
#     config_path = "tests/fixtures/api-gateway.yml"
#   }
#
#   # This assertion is relaxed for LocalStack (different URL format)
#   assert {
#     condition = var.use_localstack || can(regex("execute-api", aws_api_gateway_deployment.main.invoke_url))
#     error_message = "AWS invoke URL should contain 'execute-api' (skipped in LocalStack)"
#   }
# }

# Example 3: Test that validates core logic (mode-independent)
# run "example_parsing_test" {
#   command = plan
#
#   variables {
#     config_path = "tests/fixtures/http-events.yml"
#   }
#
#   # Parsing tests work identically in both modes
#   assert {
#     condition     = length(local.http_events) == 2
#     error_message = "Expected 2 HTTP events to be parsed"
#   }
# }

# ============================================================================
# Common LocalStack Compatibility Patterns
# ============================================================================

# IAM Validation (relaxed in LocalStack):
#   assert {
#     condition = var.use_localstack || can(regex("arn:aws:iam", aws_iam_role.lambda.arn))
#     error_message = "IAM role ARN should be valid (relaxed in LocalStack)"
#   }

# API Gateway URL Format (different in LocalStack):
#   assert {
#     condition = var.use_localstack || can(regex("execute-api.*amazonaws.com", output.api_url))
#     error_message = "API URL format differs between LocalStack and AWS"
#   }

# Resource ARNs (may have different format in LocalStack):
#   assert {
#     condition = var.use_localstack || can(regex("^arn:aws:", resource.arn))
#     error_message = "Resource ARN format may differ in LocalStack"
#   }

# ============================================================================
# References
# ============================================================================
# - LocalStack Documentation: https://docs.localstack.cloud/
# - LocalStack AWS Coverage: https://docs.localstack.cloud/user-guide/aws/feature-coverage/
# - Test Writing Guide: /docs/localstack-test-writing.md
# - Provider Config Guide: /docs/localstack-provider-config.md
