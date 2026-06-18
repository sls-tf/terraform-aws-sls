# API Gateway v2 (HTTP API) attach-to-existing tests.
#
# Exercises SAM HttpApi function events that carry an explicit ApiId: they must
# attach to the externally-managed apigatewayv2 API (aws_apigatewayv2_integration
# / _route / _authorizer) and must NOT create the self-created v1 REST API.
# A REQUEST Lambda authorizer is parsed from the AWS::Serverless::HttpApi resource.
#
# Mock AWS provider: the SAM preprocessor still runs via data.external, so no
# LocalStack or AWS credentials are needed.

mock_provider "aws" {}

# The mock provider returns random strings for region/account, which fail the
# AWS provider's execute-api source_arn ARN validation. Pin them to valid values
# so the v2 Lambda permissions plan cleanly.
override_data {
  target = data.aws_region.current
  values = {
    region = "eu-west-1"
    name   = "eu-west-1"
  }
}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
  }
}

run "http_api_v2_attaches_to_existing_api" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-http-api-v2.yaml"
    config_format = "sam"
  }

  # Three HttpApi events, all with an api_id -> all v2, none v1.
  assert {
    condition     = length(local.http_api_v2_events) == 3
    error_message = "Expected 3 HttpApi events with an ApiId on the v2 path"
  }

  assert {
    condition     = length(local.http_v1_events) == 0
    error_message = "No event should fall on the v1 REST path when every event carries an ApiId"
  }

  # The self-created v1 REST API must not be planned.
  assert {
    condition     = length(aws_api_gateway_rest_api.this) == 0
    error_message = "No v1 REST API should be created for api_id-bearing events"
  }

  # v2 integrations + routes: one per event.
  assert {
    condition     = length(aws_apigatewayv2_integration.v2) == 3
    error_message = "Expected one apigatewayv2 integration per v2 event"
  }

  assert {
    condition     = length(aws_apigatewayv2_route.v2) == 3
    error_message = "Expected one apigatewayv2 route per v2 event"
  }

  # Per-route invoke permission.
  assert {
    condition     = length(aws_lambda_permission.v2_apigw) == 3
    error_message = "Expected one Lambda invoke permission per v2 route"
  }

  # One REQUEST authorizer (referenced by two routes) + its permission.
  assert {
    condition     = length(aws_apigatewayv2_authorizer.this) == 1
    error_message = "Expected exactly one apigatewayv2 REQUEST authorizer"
  }

  assert {
    condition     = aws_apigatewayv2_authorizer.this["MachineAuthAuthorizer"].authorizer_type == "REQUEST"
    error_message = "The authorizer must be of type REQUEST"
  }

  assert {
    condition     = length(aws_lambda_permission.v2_authorizer_apigw) == 1
    error_message = "Expected one Lambda invoke permission for the authorizer"
  }

  # Route key format "<METHOD> <path>".
  assert {
    condition     = aws_apigatewayv2_route.v2["DeviceFunction-POST-sites"].route_key == "POST /sites"
    error_message = "Route key must be '<METHOD> <path>'"
  }
}
