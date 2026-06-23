# WebSocket API tests (AWS::ApiGatewayV2::Api with ProtocolType WEBSOCKET).
#
# The module must create the apigatewayv2 WEBSOCKET API, its integrations and
# routes (wired to the right functions), an auto-deploy stage, and Lambda invoke
# permissions — and must NOT raise unsupported-resource-type errors for the
# Route/Integration/Stage/Deployment sub-resources.

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

run "websocket_api_creates_resources" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-websocket.yaml"
    config_format = "sam"
  }

  assert {
    condition     = length(aws_apigatewayv2_api.websocket) == 1
    error_message = "Expected one WEBSOCKET API."
  }

  assert {
    condition     = aws_apigatewayv2_api.websocket["CommsWebSocket"].protocol_type == "WEBSOCKET"
    error_message = "API must have protocol_type WEBSOCKET."
  }

  assert {
    condition     = aws_apigatewayv2_api.websocket["CommsWebSocket"].route_selection_expression == "$request.body.action"
    error_message = "Route selection expression must be parsed."
  }

  # Two integrations ($connect, $disconnect) and two routes.
  assert {
    condition     = length(aws_apigatewayv2_integration.websocket) == 2
    error_message = "Expected two websocket integrations."
  }

  assert {
    condition     = length(aws_apigatewayv2_route.websocket) == 2
    error_message = "Expected two websocket routes."
  }

  # Routes carry the literal $connect / $disconnect keys.
  assert {
    condition     = aws_apigatewayv2_route.websocket["ConnectRoute"].route_key == "$connect"
    error_message = "ConnectRoute must have route_key $connect."
  }

  # Integration target functions are recovered from IntegrationUri: the plan only
  # succeeds (no "key does not identify an element" error) if ConnectIntegration
  # mapped to a real function logical ID. Assert the proxy type is set.
  assert {
    condition     = aws_apigatewayv2_integration.websocket["ConnectIntegration"].integration_type == "AWS_PROXY"
    error_message = "ConnectIntegration must be an AWS_PROXY integration."
  }

  # One stage, auto-deploy.
  assert {
    condition     = aws_apigatewayv2_stage.websocket["Stage"].auto_deploy == true
    error_message = "Websocket stage must auto-deploy."
  }

  # Invoke permissions, one per integration.
  assert {
    condition     = length(aws_lambda_permission.websocket) == 2
    error_message = "Expected two websocket invoke permissions."
  }

  # No unsupported-resource errors despite Route/Integration/Stage/Deployment.
  assert {
    condition     = length(local.custom_resource_validation_errors) == 0
    error_message = "Websocket sub-resources must not raise unsupported-type errors."
  }
}
