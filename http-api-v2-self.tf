# ============================================================================
# API Gateway v2 (HTTP API) — SELF-CREATED from AWS::Serverless::HttpApi
# ============================================================================
# When a SAM template declares an `AWS::Serverless::HttpApi` resource inline and
# its function events reference it with `ApiId: !Ref <HttpApiLogicalId>`, this
# file creates and owns the whole HTTP API: the apigatewayv2 API itself, its
# integrations, routes, a default auto-deploy stage, an optional REQUEST (Lambda)
# authorizer, CORS, and the Lambda invoke permissions.
#
# This is distinct from http-api-v2.tf (attach-to-existing), which is selected
# when an event's ApiId is a real external API id owned by another unit. The two
# are mutually exclusive per event: locals.http_self_v2_events vs
# locals.http_api_v2_events (see the partition in locals.tf).
#
# How the self case is detected: the SAM preprocessor cannot resolve a !Ref to a
# template resource, so `ApiId: !Ref HttpApi` arrives as the marker string
# "__UNRESOLVED__!Ref HttpApi". We strip the marker and, when the remainder names
# an AWS::Serverless::HttpApi resource in the template, route the event here.
#
# data.aws_region.current / data.aws_caller_identity.current are declared in
# main.tf and reused here.

locals {
  # Marker the SAM preprocessor emits for an unresolvable !Ref (non-strict mode).
  _unresolved_ref_prefix = "__UNRESOLVED__!Ref "

  # All AWS::Serverless::HttpApi logical IDs declared in the template (ungated by
  # resource_types — used only to CLASSIFY events so a self-targeted event never
  # leaks into the attach path with a garbage ApiId). Structural source: keys feed
  # for_each downstream, so they must be plan-known.
  sam_all_http_api_ids = var.config_format == "sam" && local.sam_structure != null ? toset([
    for logical_id, resource in try(local.sam_structure.Resources, {}) :
    logical_id
    if try(resource.Type, "") == "AWS::Serverless::HttpApi"
  ]) : toset([])

  # Reverse map: resolved Lambda function name OR logical ID -> function logical
  # ID. An authorizer's FunctionArn/FunctionInvokeArn resolves (via the
  # preprocessor) to an ARN whose trailing segment is the resource's *resolved*
  # name — which equals the explicit FunctionName when one is set, else the
  # logical ID. This lets us recover the logical ID either way so
  # aws_lambda_function.functions[<logicalId>] resolves.
  # Includes three key forms so a reference resolves regardless of which parse it
  # came from: the logical ID; the RESOLVED FunctionName (resolved parse, uses
  # caller parameter values); and the STRUCTURAL FunctionName (resolved against
  # template Defaults). The last matters because cross-resource references
  # (WebSocket IntegrationUri, authorizer FunctionArn) are read from the
  # structural parse, where a parameter like Enviroment takes its Default — which
  # can differ from the value the caller passes for the resolved parse.
  _function_name_to_logical = merge(
    { for lid in local._function_names : lid => lid },
    {
      for lid in local._function_names :
      tostring(local.functions_with_defaults[lid].name) => lid
      if try(local.functions_with_defaults[lid].name, null) != null
    },
    {
      for lid in local._function_names :
      tostring(try(local.sam_structure.Resources[lid].Properties.FunctionName, "")) => lid
      if var.config_format == "sam" && local.sam_structure != null && tostring(try(local.sam_structure.Resources[lid].Properties.FunctionName, "")) != ""
    }
  )

  # HTTP events that target a SELF-created HttpApi: ApiId is a !Ref to a template
  # AWS::Serverless::HttpApi resource. Carries the resolved api logical ID.
  http_self_v2_events = [
    for event in local.http_events :
    merge(event, {
      self_api_logical_id = replace(tostring(event.api_id), local._unresolved_ref_prefix, "")
    })
    if event.api_id != null && contains(local.sam_all_http_api_ids, replace(tostring(event.api_id), local._unresolved_ref_prefix, ""))
  ]

  # The set of self HttpApi logical IDs to actually CREATE — derived from the
  # events that reference them, then gated by the resource_types allowlist. An
  # HttpApi resource referenced by no !Ref event (e.g. an authorizer-only shared
  # API) is not self-created here.
  sam_self_http_apis = toset([
    for event in local.http_self_v2_events :
    event.self_api_logical_id
    if var.resource_types == null || contains(var.resource_types, "AWS::Serverless::HttpApi")
  ])

  # Per self-API properties (CORS etc.) from the structural parse (literals, so
  # always plan-known).
  sam_self_http_api_props = {
    for lid in local.sam_self_http_apis :
    lid => try(local.sam_structure.Resources[lid].Properties, {})
  }

  # Keyed integration/route map for the self path:
  # "<function>-<METHOD>-<sanitized_path>" -> event (only for created APIs).
  http_self_v2_event_map = {
    for event in local.http_self_v2_events :
    "${event.function_name}-${upper(event.http_method)}-${replace(replace(replace(trimprefix(event.http_path, "/"), "/", "_"), "{", ""), "}", "")}" => event
    if contains(local.sam_self_http_apis, event.self_api_logical_id)
  }

  # Resolved authorizer defs for the self path, keyed by authorizer name. Each is
  # attached to the self API named by the event(s) that reference it.
  http_self_v2_authorizers = {
    for auth_name, auth_def in local.sam_http_api_authorizers :
    auth_name => merge(auth_def, {
      api_logical_id = try([
        for event in local.http_self_v2_events :
        event.self_api_logical_id if event.authorizer == auth_name
      ][0], null)
      # Map the parsed function_ref (resolved name or logical ID) back to a
      # function logical ID so aws_lambda_function.functions[...] resolves.
      function_name = try(local._function_name_to_logical[auth_def.function_ref], auth_def.function_ref)
    })
    if length([
      for event in local.http_self_v2_events :
      event if event.authorizer == auth_name && contains(local.sam_self_http_apis, event.self_api_logical_id)
    ]) > 0
  }
}

# The HTTP API itself.
resource "aws_apigatewayv2_api" "self" {
  for_each = local.sam_self_http_apis

  name          = try(local.sam_self_http_api_props[each.key].Name, "${try(local.parsed_config_resolved.service, "sam-service")}-${local.provider_with_defaults.stage}-${each.key}")
  protocol_type = "HTTP"

  dynamic "cors_configuration" {
    for_each = try(local.sam_self_http_api_props[each.key].CorsConfiguration, null) != null ? [local.sam_self_http_api_props[each.key].CorsConfiguration] : []
    content {
      allow_headers     = try(cors_configuration.value.AllowHeaders, null)
      allow_methods     = try(cors_configuration.value.AllowMethods, null)
      allow_origins     = try(cors_configuration.value.AllowOrigins, null)
      expose_headers    = try(cors_configuration.value.ExposeHeaders, null)
      max_age           = try(cors_configuration.value.MaxAge, null)
      allow_credentials = try(cors_configuration.value.AllowCredentials, null)
    }
  }

  tags = {
    Name      = each.key
    ManagedBy = "sls.tf"
    LogicalId = each.key
    Stage     = local.provider_with_defaults.stage
  }

  depends_on = [null_resource.config_validation]
}

# AWS_PROXY integration per route.
resource "aws_apigatewayv2_integration" "self" {
  for_each = local.http_self_v2_event_map

  api_id                 = aws_apigatewayv2_api.self[each.value.self_api_logical_id].id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.functions[each.value.function_name].invoke_arn
  integration_method     = "POST"
  payload_format_version = each.value.payload_format_version

  depends_on = [null_resource.config_validation]
}

# Route ("<METHOD> <path>"). With an authorizer the route uses CUSTOM auth.
resource "aws_apigatewayv2_route" "self" {
  for_each = local.http_self_v2_event_map

  api_id    = aws_apigatewayv2_api.self[each.value.self_api_logical_id].id
  route_key = "${upper(each.value.http_method)} ${each.value.http_path}"
  target    = "integrations/${aws_apigatewayv2_integration.self[each.key].id}"

  authorization_type = each.value.authorizer != null ? "CUSTOM" : "NONE"
  authorizer_id      = each.value.authorizer != null ? aws_apigatewayv2_authorizer.self[each.value.authorizer].id : null
}

# Default auto-deploy stage. SAM's AWS::Serverless::HttpApi provisions an
# implicit "$default" stage with auto-deploy; we mirror that.
resource "aws_apigatewayv2_stage" "self" {
  for_each = local.sam_self_http_apis

  api_id      = aws_apigatewayv2_api.self[each.key].id
  name        = "$default"
  auto_deploy = true

  tags = {
    Name      = each.key
    ManagedBy = "sls.tf"
    LogicalId = each.key
  }

  depends_on = [aws_apigatewayv2_route.self]
}

# REQUEST (Lambda) authorizer on the self API.
resource "aws_apigatewayv2_authorizer" "self" {
  for_each = local.http_self_v2_authorizers

  api_id                            = aws_apigatewayv2_api.self[each.value.api_logical_id].id
  name                              = each.key
  authorizer_type                   = "REQUEST"
  authorizer_uri                    = "arn:aws:apigateway:${data.aws_region.current.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.functions[each.value.function_name].arn}/invocations"
  identity_sources                  = each.value.identity_sources
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = each.value.enable_simple_responses
  authorizer_result_ttl_in_seconds  = each.value.result_ttl

  depends_on = [null_resource.config_validation]
}

# Allow the self API to invoke each route's Lambda.
resource "aws_lambda_permission" "self_apigw" {
  for_each = local.http_self_v2_event_map

  statement_id  = "AllowSelfHttpApiInvoke-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.functions[each.value.function_name].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.self[each.value.self_api_logical_id].id}/*/*"
}

# Allow the self API to invoke the authorizer Lambda.
resource "aws_lambda_permission" "self_authorizer_apigw" {
  for_each = local.http_self_v2_authorizers

  statement_id  = "AllowSelfHttpApiInvokeAuthorizer-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.functions[each.value.function_name].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.self[each.value.api_logical_id].id}/authorizers/${aws_apigatewayv2_authorizer.self[each.key].id}"
}
