# ============================================================================
# API Gateway v2 — WebSocket API (AWS::ApiGatewayV2::Api, ProtocolType WEBSOCKET)
# ============================================================================
# A SAM/CloudFormation template can declare a WebSocket API as raw
# AWS::ApiGatewayV2::Api (ProtocolType: WEBSOCKET) plus AWS::ApiGatewayV2::Route,
# ::Integration and ::Stage sub-resources, wiring routes ($connect, $disconnect,
# custom actions) to Lambda integrations.
#
# This file detects that shape and creates the equivalent Terraform resources:
# aws_apigatewayv2_api (WEBSOCKET) + _integration (AWS_PROXY) + _route + _stage
# (auto-deploy) + the Lambda invoke permissions.
#
# Resources intentionally SUBSUMED (recognized, not separately created):
#   - AWS::ApiGatewayV2::Deployment — replaced by stage auto_deploy.
#   - AWS::Lambda::Permission       — the module emits its own invoke permissions.
# Both are added to local.supported_resource_types so they do not raise
# "unsupported resource type" validation errors.
#
# Cross-references resolve via the SAM preprocessor markers: ApiId/Target carry
# `!Ref <LogicalId>` as the marker string "__UNRESOLVED__!Ref <LogicalId>"
# (see local._unresolved_ref_prefix); IntegrationUri embeds the target function's
# resolved ARN (`...:function:<name>...`), from which the function logical ID is
# recovered via local._function_name_to_logical.
#
# All maps are built from local._custom_resources_structure (the plan-time-known
# structural parse), so for_each keys stay known even on greenfield.

locals {
  # WebSocket APIs: AWS::ApiGatewayV2::Api with ProtocolType WEBSOCKET, gated by
  # the resource_types allowlist. Keyed by logical ID.
  websocket_apis = {
    for logical_id, resource in local._custom_resources_structure :
    logical_id => resource
    if try(resource.Type, "") == "AWS::ApiGatewayV2::Api"
    && upper(tostring(try(resource.Properties.ProtocolType, ""))) == "WEBSOCKET"
    && (var.resource_types == null || contains(var.resource_types, "AWS::ApiGatewayV2::Api"))
  }

  _websocket_api_ids = toset(keys(local.websocket_apis))

  # Integrations attached to a websocket API. function_name is the function's
  # logical ID, recovered from the IntegrationUri's trailing :function:<name>.
  websocket_integrations = {
    for logical_id, resource in local._custom_resources_structure :
    logical_id => {
      api_logical_id = replace(tostring(try(resource.Properties.ApiId, "")), local._unresolved_ref_prefix, "")
      # regex() with a capture group returns a LIST of captures; [0] is the
      # function's resolved name, mapped back to its logical ID.
      function_name = try(
        local._function_name_to_logical[regex("function:([^/]+)", tostring(try(resource.Properties.IntegrationUri, "")))[0]],
        ""
      )
    }
    if try(resource.Type, "") == "AWS::ApiGatewayV2::Integration"
    && contains(local._websocket_api_ids, replace(tostring(try(resource.Properties.ApiId, "")), local._unresolved_ref_prefix, ""))
  }

  # Routes attached to a websocket API. integration_logical_id is recovered from
  # the Target ("integrations/<IntegrationLogicalId>").
  websocket_routes = {
    for logical_id, resource in local._custom_resources_structure :
    logical_id => {
      api_logical_id = replace(tostring(try(resource.Properties.ApiId, "")), local._unresolved_ref_prefix, "")
      route_key      = tostring(try(resource.Properties.RouteKey, logical_id))
      integration_logical_id = replace(
        element(
          split("/", tostring(try(resource.Properties.Target, ""))),
          length(split("/", tostring(try(resource.Properties.Target, "")))) - 1
        ),
        local._unresolved_ref_prefix, ""
      )
      authorization_type = tostring(try(resource.Properties.AuthorizationType, "NONE"))
    }
    if try(resource.Type, "") == "AWS::ApiGatewayV2::Route"
    && contains(local._websocket_api_ids, replace(tostring(try(resource.Properties.ApiId, "")), local._unresolved_ref_prefix, ""))
  }

  # Stages attached to a websocket API.
  websocket_stages = {
    for logical_id, resource in local._custom_resources_structure :
    logical_id => {
      api_logical_id = replace(tostring(try(resource.Properties.ApiId, "")), local._unresolved_ref_prefix, "")
      stage_name     = tostring(try(resource.Properties.StageName, local.provider_with_defaults.stage))
    }
    if try(resource.Type, "") == "AWS::ApiGatewayV2::Stage"
    && contains(local._websocket_api_ids, replace(tostring(try(resource.Properties.ApiId, "")), local._unresolved_ref_prefix, ""))
  }
}

resource "aws_apigatewayv2_api" "websocket" {
  for_each = local.websocket_apis

  name                       = tostring(try(each.value.Properties.Name, "${try(local.parsed_config_resolved.service, "sam-service")}-${local.provider_with_defaults.stage}-${each.key}"))
  protocol_type              = "WEBSOCKET"
  route_selection_expression = tostring(try(each.value.Properties.RouteSelectionExpression, "$request.body.action"))

  tags = {
    Name      = each.key
    ManagedBy = "sls.tf"
    LogicalId = each.key
    Stage     = local.provider_with_defaults.stage
  }

  depends_on = [null_resource.config_validation]
}

resource "aws_apigatewayv2_integration" "websocket" {
  for_each = local.websocket_integrations

  api_id           = aws_apigatewayv2_api.websocket[each.value.api_logical_id].id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.functions[each.value.function_name].invoke_arn

  depends_on = [null_resource.config_validation]
}

resource "aws_apigatewayv2_route" "websocket" {
  for_each = local.websocket_routes

  api_id             = aws_apigatewayv2_api.websocket[each.value.api_logical_id].id
  route_key          = each.value.route_key
  target             = "integrations/${aws_apigatewayv2_integration.websocket[each.value.integration_logical_id].id}"
  authorization_type = each.value.authorization_type
}

resource "aws_apigatewayv2_stage" "websocket" {
  for_each = local.websocket_stages

  api_id      = aws_apigatewayv2_api.websocket[each.value.api_logical_id].id
  name        = each.value.stage_name
  auto_deploy = true

  tags = {
    Name      = each.key
    ManagedBy = "sls.tf"
    LogicalId = each.key
  }

  depends_on = [aws_apigatewayv2_route.websocket]
}

# Allow the websocket API to invoke each route's Lambda. Keyed per integration.
resource "aws_lambda_permission" "websocket" {
  for_each = local.websocket_integrations

  statement_id  = "AllowWebSocketInvoke-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.functions[each.value.function_name].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.websocket[each.value.api_logical_id].id}/*/*"
}
