# ============================================================================
# API Gateway v2 (HTTP API) — attach to an EXISTING/shared API
# ============================================================================
# When a SAM HttpApi function event carries an `ApiId` (parsed into
# event.api_id, see sam-parser.tf / locals.tf), the route attaches to an
# externally-managed apigatewayv2 API rather than the self-created v1 REST API
# in main.tf. This mirrors the hand-written device-service api-gateway.tf:
# AWS_PROXY integration (payload 2.0) + route ("METHOD /path") + invoke
# permission, plus an optional REQUEST (Lambda) authorizer.
#
# The shared API itself (aws_apigatewayv2_api) is NOT managed here — it is owned
# by the platform/gateway unit. We only emit integrations, routes, authorizers,
# and the Lambda permissions that let that API invoke our functions.
#
# data.aws_region.current / data.aws_caller_identity.current are declared in
# main.tf and reused here.

# AWS_PROXY integration per v2 route.
resource "aws_apigatewayv2_integration" "v2" {
  for_each = local.http_api_v2_event_map

  api_id                 = each.value.api_id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.functions[each.value.function_name].invoke_arn
  integration_method     = "POST"
  payload_format_version = each.value.payload_format_version

  depends_on = [null_resource.config_validation]
}

# Route ("<METHOD> <path>") targeting the integration above. When the event
# names an authorizer, the route uses CUSTOM authorization wired to the
# apigatewayv2 authorizer emitted below.
resource "aws_apigatewayv2_route" "v2" {
  for_each = local.http_api_v2_event_map

  api_id    = each.value.api_id
  route_key = "${upper(each.value.http_method)} ${each.value.http_path}"
  target    = "integrations/${aws_apigatewayv2_integration.v2[each.key].id}"

  authorization_type = each.value.authorizer != null ? "CUSTOM" : null
  authorizer_id      = each.value.authorizer != null ? aws_apigatewayv2_authorizer.this[each.value.authorizer].id : null
}

# Allow the shared API to invoke the route's Lambda. source_arn uses the
# api_id-scoped execute-api ARN with wildcard stage/route (matches device-service).
resource "aws_lambda_permission" "v2_apigw" {
  for_each = local.http_api_v2_event_map

  statement_id  = "AllowAPIGatewayV2Invoke-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.functions[each.value.function_name].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${each.value.api_id}/*/*"
}

# ----------------------------------------------------------------------------
# REQUEST (Lambda) authorizer on the shared API
# ----------------------------------------------------------------------------
# for_each over the resolved authorizer defs (locals.http_api_v2_authorizers),
# keyed by authorizer name. authorizer_uri is the standard apigateway lambda
# invoke path for the authorizer Function.
resource "aws_apigatewayv2_authorizer" "this" {
  for_each = local.http_api_v2_authorizers

  api_id                            = each.value.api_id
  name                              = each.key
  authorizer_type                   = "REQUEST"
  authorizer_uri                    = "arn:aws:apigateway:${data.aws_region.current.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.functions[each.value.function_name].arn}/invocations"
  identity_sources                  = each.value.identity_sources
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = each.value.enable_simple_responses
  authorizer_result_ttl_in_seconds  = each.value.result_ttl

  depends_on = [null_resource.config_validation]
}

# Allow the shared API to invoke the authorizer Lambda.
resource "aws_lambda_permission" "v2_authorizer_apigw" {
  for_each = local.http_api_v2_authorizers

  statement_id  = "AllowAPIGatewayV2InvokeAuthorizer-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.functions[each.value.function_name].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${each.value.api_id}/authorizers/${aws_apigatewayv2_authorizer.this[each.key].id}"
}
