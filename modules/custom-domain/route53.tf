# ============================================================================
# Route 53 Resources
# ============================================================================

# Create new hosted zone if needed
# Only created when create_hosted_zone=true AND hostedZoneId not provided
resource "aws_route53_zone" "custom_domain" {
  count = var.create_hosted_zone && try(var.domain_config.hostedZoneId, null) == null ? 1 : 0
  name  = var.domain_config.domainName
}

# Create ALIAS record pointing to API Gateway endpoint
# ALIAS records are used instead of A records (AWS-native, no query limits)
resource "aws_route53_record" "custom_domain" {
  count   = local.custom_domain_config.createRoute53Record ? 1 : 0
  zone_id = local.hosted_zone_id
  name    = var.domain_config.domainName
  type    = "A"

  alias {
    name                   = local.domain_name_target
    zone_id                = local.domain_name_zone_id
    evaluate_target_health = true
  }

  depends_on = [aws_api_gateway_domain_name.custom_domain]
}
