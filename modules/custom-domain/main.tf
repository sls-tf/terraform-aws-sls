# ============================================================================
# Configuration Parsing & Default Application
# ============================================================================

locals {
  # Apply customDomain defaults matching Serverless Framework behavior
  custom_domain_config = var.domain_config != null ? merge(
    var.domain_config,
    {
      createRoute53Record = coalesce(try(var.domain_config.createRoute53Record, null), true)
      endpointType        = coalesce(try(var.domain_config.endpointType, null), "EDGE")
      stage               = coalesce(try(var.domain_config.stage, null), var.api_gateway_stage)
    }
  ) : null

  # Certificate ARN resolution: config takes precedence over module variable
  certificate_arn = coalesce(
    try(var.domain_config.certificateArn, null),
    var.acm_certificate_arn
  )

  # Extract region from certificate ARN for validation
  certificate_region = local.certificate_arn != null ? split(":", local.certificate_arn)[3] : null

  # Define required region based on endpoint type
  required_region = local.custom_domain_config.endpointType == "EDGE" ? "us-east-1" : var.aws_region

  # Hosted zone resolution: config, created zone, or looked-up zone
  hosted_zone_id = coalesce(
    try(var.domain_config.hostedZoneId, null),
    try(aws_route53_zone.custom_domain[0].zone_id, null),
    try(data.aws_route53_zone.existing[0].zone_id, null)
  )

  # Domain name target selection based on endpoint type
  domain_name_target = local.custom_domain_config.endpointType == "EDGE" ? (
    aws_api_gateway_domain_name.custom_domain.cloudfront_domain_name
    ) : (
    aws_api_gateway_domain_name.custom_domain.regional_domain_name
  )

  domain_name_zone_id = local.custom_domain_config.endpointType == "EDGE" ? (
    aws_api_gateway_domain_name.custom_domain.cloudfront_zone_id
    ) : (
    aws_api_gateway_domain_name.custom_domain.regional_zone_id
  )
}

# ============================================================================
# API Gateway Custom Domain Name
# ============================================================================

# API Gateway custom domain name
# EDGE endpoints use CloudFront distribution, REGIONAL uses regional endpoint
resource "aws_api_gateway_domain_name" "custom_domain" {
  domain_name     = var.domain_config.domainName
  certificate_arn = local.certificate_arn

  endpoint_configuration {
    types = [local.custom_domain_config.endpointType]
  }
}

# ============================================================================
# Base Path Mapping
# ============================================================================

# Base path mapping to API stage
resource "aws_api_gateway_base_path_mapping" "custom_domain" {
  domain_name = aws_api_gateway_domain_name.custom_domain.domain_name
  api_id      = var.api_gateway_rest_api
  stage_name  = local.custom_domain_config.stage
  base_path   = try(var.domain_config.basePath, null)

  depends_on = [aws_api_gateway_domain_name.custom_domain]
}
