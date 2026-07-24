# Test: Direct API Gateway -> EventBridge integration (no Lambda in the path)
# Raw AWS::ApiGatewayV2::Integration (IntegrationSubtype EventBridge-PutEvents)
# + Route on a self-created AWS::Serverless::HttpApi; request transform via
# RequestParameters; auto-created credentials role.

mock_provider "aws" {}

run "direct_integration_created" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-httpapi-direct.yaml"
    config_format = "sam"
  }

  # The API is created even though NO function event references it — direct
  # integrations alone drive self-API creation.
  assert {
    condition     = length(aws_apigatewayv2_api.self) == 1
    error_message = "Self HTTP API not created for direct-only integration"
  }

  assert {
    condition     = length(aws_apigatewayv2_integration.direct) == 1
    error_message = "Expected 1 direct integration, got ${length(aws_apigatewayv2_integration.direct)}"
  }

  assert {
    condition     = length(aws_apigatewayv2_route.direct) == 1
    error_message = "Expected 1 direct route, got ${length(aws_apigatewayv2_route.direct)}"
  }

  # No Lambda anywhere in the path
  assert {
    condition     = length(aws_apigatewayv2_integration.self) == 0
    error_message = "No Lambda integrations expected"
  }
}

run "direct_integration_properties" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-httpapi-direct.yaml"
    config_format = "sam"
  }

  assert {
    condition     = aws_apigatewayv2_integration.direct["EventsIntegration"].integration_type == "AWS_PROXY"
    error_message = "Integration type not translated"
  }

  assert {
    condition     = aws_apigatewayv2_integration.direct["EventsIntegration"].integration_subtype == "EventBridge-PutEvents"
    error_message = "IntegrationSubtype not translated"
  }

  assert {
    condition     = aws_apigatewayv2_integration.direct["EventsIntegration"].payload_format_version == "1.0"
    error_message = "Payload format version not translated"
  }

  # The request template transform
  assert {
    condition     = aws_apigatewayv2_integration.direct["EventsIntegration"].request_parameters["Detail"] == "$request.body"
    error_message = "RequestParameters Detail transform not translated"
  }

  assert {
    condition     = aws_apigatewayv2_integration.direct["EventsIntegration"].request_parameters["Source"] == "api.events"
    error_message = "RequestParameters Source not translated"
  }
}

run "direct_route_properties" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-httpapi-direct.yaml"
    config_format = "sam"
  }

  assert {
    condition     = aws_apigatewayv2_route.direct["EventsRoute"].route_key == "POST /events"
    error_message = "Direct route key not translated"
  }
}

run "auto_credentials_role" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-httpapi-direct.yaml"
    config_format = "sam"
  }

  # No CredentialsArn declared -> module creates a PutEvents role
  assert {
    condition     = length(aws_iam_role.http_direct_integration) == 1
    error_message = "Auto credentials role not created"
  }

  assert {
    condition     = can(regex("events:PutEvents", aws_iam_role_policy.http_direct_integration["EventsIntegration"].policy))
    error_message = "Auto role policy missing events:PutEvents"
  }
}
