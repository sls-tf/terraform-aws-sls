# ============================================================================
# Direct (non-Lambda) HTTP API integrations — API Gateway service integrations
# ============================================================================
# Every function-event route on a self-created HttpApi assumes a Lambda target.
# This file covers routes with NO Lambda in the path: raw
# AWS::ApiGatewayV2::Integration resources with an IntegrationSubtype (e.g.
# EventBridge-PutEvents, SQS-SendMessage) attached to a template
# AWS::Serverless::HttpApi, plus the AWS::ApiGatewayV2::Route resources that
# reference them. The request transform lives in RequestParameters.
#
# CredentialsArn resolution: {Fn::GetAtt: [Role, Arn]} / a resolved "role/<name>"
# ARN maps to a template AWS::IAM::Role (aws_iam_role.custom); a literal external
# ARN passes through. When no credentials are declared and the subtype is an
# EventBridge one, the module creates a minimal events:PutEvents role.
#
# Websocket Integration/Route resources are unaffected: those attach to an
# AWS::ApiGatewayV2::Api, these attach to an AWS::Serverless::HttpApi.

locals {
  # Direct integrations on a template HttpApi. Keyed by logical ID; structure
  # from the structural parse, values from the resolved parse.
  http_direct_integrations = {
    for logical_id, resource in local._custom_resources_structure :
    logical_id => {
      api_logical_id      = replace(tostring(try(resource.Properties.ApiId, "")), local._unresolved_ref_prefix, "")
      integration_type    = tostring(try(resource.Properties.IntegrationType, "AWS_PROXY"))
      integration_subtype = tostring(try(resource.Properties.IntegrationSubtype, ""))
      # Request mapping (the transform): map of string parameters.
      request_parameters = {
        for k, v in try(local.custom_resources_raw[logical_id].Properties.RequestParameters, {}) :
        k => try(tostring(v), jsonencode(v))
      }
      credentials_raw          = try(local.custom_resources_raw[logical_id].Properties.CredentialsArn, null)
      has_declared_credentials = try(local._custom_resources_structure[logical_id].Properties.CredentialsArn, null) != null
      payload_format_version   = tostring(try(resource.Properties.PayloadFormatVersion, "1.0"))
      description              = try(resource.Properties.Description, null)
    }
    if try(resource.Type, "") == "AWS::ApiGatewayV2::Integration"
    && contains(local.sam_all_http_api_ids, replace(tostring(try(resource.Properties.ApiId, "")), local._unresolved_ref_prefix, ""))
  }

  # Direct integrations with no declared credentials get an auto-created role
  # scoped to the subtype's service action (EventBridge PutEvents today).
  http_direct_auto_role_integrations = {
    for logical_id, integration in local.http_direct_integrations :
    logical_id => integration
    if !integration.has_declared_credentials && startswith(integration.integration_subtype, "EventBridge")
  }

  # Routes referencing a direct integration. integration_logical_id recovered
  # from Target ("integrations/<IntegrationLogicalId>"), same as websocket.
  http_direct_routes = {
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
    && contains(local.sam_all_http_api_ids, replace(tostring(try(resource.Properties.ApiId, "")), local._unresolved_ref_prefix, ""))
  }
}

resource "aws_apigatewayv2_integration" "direct" {
  for_each = local.http_direct_integrations

  api_id              = aws_apigatewayv2_api.self[each.value.api_logical_id].id
  integration_type    = each.value.integration_type
  integration_subtype = each.value.integration_subtype != "" ? each.value.integration_subtype : null
  description         = each.value.description

  # Service integrations (subtype set) require payload format 1.0 and use
  # request_parameters as the request transform.
  payload_format_version = each.value.payload_format_version
  request_parameters     = each.value.request_parameters

  credentials_arn = try(
    aws_iam_role.custom[each.value.credentials_raw["Fn::GetAtt"][0]].arn,
    aws_iam_role.custom[local._iam_role_name_to_logical[regex("role/([^/]+)$", tostring(each.value.credentials_raw))[0]]].arn,
    tostring(each.value.credentials_raw),
    aws_iam_role.http_direct_integration[each.key].arn,
    null
  )

  depends_on = [null_resource.config_validation]
}

resource "aws_apigatewayv2_route" "direct" {
  for_each = local.http_direct_routes

  api_id             = aws_apigatewayv2_api.self[each.value.api_logical_id].id
  route_key          = each.value.route_key
  target             = "integrations/${aws_apigatewayv2_integration.direct[each.value.integration_logical_id].id}"
  authorization_type = each.value.authorization_type
}

# Minimal role letting API Gateway put events on EventBridge, for direct
# EventBridge integrations that declare no CredentialsArn.
resource "aws_iam_role" "http_direct_integration" {
  for_each = local.http_direct_auto_role_integrations

  name = "${try(local.parsed_config_resolved.service, "sam-service")}-${local.provider_with_defaults.stage}-${each.key}-apigw"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "apigateway.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name      = each.key
    ManagedBy = "sls.tf"
    LogicalId = each.key
  }

  depends_on = [null_resource.config_validation]
}

resource "aws_iam_role_policy" "http_direct_integration" {
  for_each = local.http_direct_auto_role_integrations

  name = "eventbridge-put-events"
  role = aws_iam_role.http_direct_integration[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "events:PutEvents"
      Resource = "*"
    }]
  })
}
