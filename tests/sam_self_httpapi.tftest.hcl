# Self-created AWS::Serverless::HttpApi (v2) tests.
#
# A SAM template declares an HttpApi resource inline and its function events
# reference it via `ApiId: !Ref HttpApi`. The module must self-create the
# apigatewayv2 API, integrations, routes, a default stage, the REQUEST
# authorizer, and the Lambda permissions — and must NOT create the self-created
# v1 REST API or the attach-to-existing v2 resources.
#
# Mock AWS provider: the SAM preprocessor still runs via data.external (node).

mock_provider "aws" {}

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

run "self_httpapi_creates_v2_api_and_routes" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-self-httpapi.yaml"
    config_format = "sam"
  }

  # One self-created HTTP API.
  assert {
    condition     = length(aws_apigatewayv2_api.self) == 1
    error_message = "Expected exactly one self-created apigatewayv2 API."
  }

  assert {
    condition     = aws_apigatewayv2_api.self["HttpApi"].protocol_type == "HTTP"
    error_message = "Self HTTP API must have protocol_type HTTP."
  }

  # Two HttpApi events -> two integrations and two routes.
  assert {
    condition     = length(aws_apigatewayv2_integration.self) == 2
    error_message = "Expected two self HTTP API integrations (saveStream, videos/{panelID})."
  }

  assert {
    condition     = length(aws_apigatewayv2_route.self) == 2
    error_message = "Expected two self HTTP API routes."
  }

  # The REQUEST authorizer is created and attached.
  assert {
    condition     = length(aws_apigatewayv2_authorizer.self) == 1
    error_message = "Expected one self HTTP API REQUEST authorizer."
  }

  assert {
    condition     = aws_apigatewayv2_authorizer.self["TexecomCloudAuth"].authorizer_type == "REQUEST"
    error_message = "Authorizer must be REQUEST type."
  }

  # A default ($default) auto-deploy stage.
  assert {
    condition     = aws_apigatewayv2_stage.self["HttpApi"].name == "$default"
    error_message = "Self HTTP API stage must be $default."
  }

  # Routes must use CUSTOM authorization (they reference the authorizer).
  assert {
    condition = alltrue([
      for k, r in aws_apigatewayv2_route.self : r.authorization_type == "CUSTOM"
    ])
    error_message = "Authorized routes must use CUSTOM authorization."
  }

  # Must NOT fall back to the v1 REST API.
  assert {
    condition     = length(aws_api_gateway_rest_api.this) == 0
    error_message = "Self HttpApi events must not create the v1 REST API."
  }

  # Must NOT create attach-to-existing v2 resources.
  assert {
    condition     = length(aws_apigatewayv2_integration.v2) == 0
    error_message = "Self HttpApi events must not use the attach-to-existing path."
  }

  # Lambda invoke permissions: one per route + one for the authorizer.
  assert {
    condition     = length(aws_lambda_permission.self_apigw) == 2
    error_message = "Expected two route invoke permissions."
  }

  assert {
    condition     = length(aws_lambda_permission.self_authorizer_apigw) == 1
    error_message = "Expected one authorizer invoke permission."
  }
}
