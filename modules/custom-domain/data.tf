# ============================================================================
# Route 53 Data Sources
# ============================================================================

# Lookup existing hosted zone if hostedZoneId provided in configuration
data "aws_route53_zone" "existing" {
  count   = try(var.domain_config.hostedZoneId, null) != null ? 1 : 0
  zone_id = var.domain_config.hostedZoneId
}
