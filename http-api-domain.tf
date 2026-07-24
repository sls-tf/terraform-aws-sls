# ============================================================================
# HTTP API custom domain (AWS::Serverless::HttpApi `Domain` property)
# ============================================================================
# SAM's HttpApi Domain shorthand provisions a custom domain on top of the HTTP
# API: an API Gateway v2 domain name (with an ACM certificate), API mappings
# onto the $default stage (one per BasePath entry), and optionally a Route53
# alias record when Route53.HostedZoneId is given.
#
# Properties are read from the STRUCTURAL parse (sam_self_http_api_props), so
# the presence tests and mapping keys stay plan-known.

locals {
  # Self HTTP APIs that declare a Domain.
  sam_self_http_api_domains = {
    for lid in local.sam_self_http_apis :
    lid => local.sam_self_http_api_props[lid].Domain
    if try(local.sam_self_http_api_props[lid].Domain, null) != null
  }

  # One API mapping per BasePath entry; a missing/empty BasePath yields the
  # single root mapping. BasePath may be a list (SAM-native) or a scalar.
  sam_self_http_api_domain_mappings = {
    for pair in flatten([
      for lid, domain in local.sam_self_http_api_domains : [
        for base_path in try(
          [for p in domain.BasePath : tostring(p)],
          [tostring(try(domain.BasePath, ""))]
          ) : {
          key       = "${lid}-${trimprefix(base_path, "/")}"
          lid       = lid
          base_path = trimprefix(base_path, "/")
        }
      ]
    ]) : pair.key => pair
  }

  # Domains that also want a Route53 alias record.
  sam_self_http_api_domain_route53 = {
    for lid, domain in local.sam_self_http_api_domains :
    lid => domain
    if try(domain.Route53.HostedZoneId, null) != null
  }
}

resource "aws_apigatewayv2_domain_name" "self" {
  for_each = local.sam_self_http_api_domains

  domain_name = tostring(each.value.DomainName)

  domain_name_configuration {
    certificate_arn = tostring(each.value.CertificateArn)
    # HTTP APIs only support REGIONAL endpoints.
    endpoint_type   = "REGIONAL"
    security_policy = tostring(try(each.value.SecurityPolicy, "TLS_1_2"))
  }

  tags = {
    Name      = each.key
    ManagedBy = "sls.tf"
    LogicalId = each.key
    Stage     = local.provider_with_defaults.stage
  }

  depends_on = [null_resource.config_validation]
}

resource "aws_apigatewayv2_api_mapping" "self" {
  for_each = local.sam_self_http_api_domain_mappings

  api_id          = aws_apigatewayv2_api.self[each.value.lid].id
  domain_name     = aws_apigatewayv2_domain_name.self[each.value.lid].id
  stage           = aws_apigatewayv2_stage.self[each.value.lid].id
  api_mapping_key = each.value.base_path != "" ? each.value.base_path : null
}

resource "aws_route53_record" "self_httpapi" {
  for_each = local.sam_self_http_api_domain_route53

  zone_id = tostring(each.value.Route53.HostedZoneId)
  name    = tostring(each.value.DomainName)
  type    = "A"

  alias {
    name                   = aws_apigatewayv2_domain_name.self[each.key].domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.self[each.key].domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}
