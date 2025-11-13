# ============================================================================
# Validation Logic
# ============================================================================

locals {
  # Required field validation
  required_field_errors = var.domain_config == null || try(var.domain_config.domainName, "") == "" ? [
    "Field 'customDomain.domainName' is required when customDomain block is present."
  ] : []

  # Domain name format validation (RFC 1123)
  format_validation_errors = var.domain_config != null && !can(regex("^[a-z0-9][a-z0-9-\\.]*[a-z0-9]$", var.domain_config.domainName)) ? [
    "Field 'customDomain.domainName' must be a valid DNS hostname (RFC 1123 format)."
  ] : []

  # Base path format validation
  base_path_errors = try(var.domain_config.basePath, null) != null && (
    can(regex("^/", var.domain_config.basePath)) ||
    can(regex("/$", var.domain_config.basePath)) ||
    !can(regex("^[a-zA-Z0-9_-]+$", var.domain_config.basePath))
    ) ? [
    "Field 'customDomain.basePath' must contain only alphanumeric characters, hyphens, and underscores with no leading or trailing slashes. Got: '${var.domain_config.basePath}'"
  ] : []

  # Endpoint type validation
  valid_endpoint_types = ["EDGE", "REGIONAL", "PRIVATE"]
  endpoint_type_errors = var.domain_config != null && !contains(local.valid_endpoint_types, local.custom_domain_config.endpointType) ? [
    "Field 'customDomain.endpointType' must be one of: EDGE, REGIONAL, PRIVATE. Got: '${local.custom_domain_config.endpointType}'"
  ] : []

  # Certificate ARN validation - ensure certificate provided from either source
  certificate_required_errors = local.certificate_arn == null ? [
    "ACM certificate ARN required for custom domain. Provide via customDomain.certificateArn or acm_certificate_arn module variable."
  ] : []

  # Certificate ARN format validation
  certificate_format_errors = local.certificate_arn != null && !can(regex("^arn:aws:acm:[a-z0-9-]+:[0-9]+:certificate/[a-z0-9-]+$", local.certificate_arn)) ? [
    "Certificate ARN must be a valid AWS ARN format: arn:aws:acm:region:account:certificate/id"
  ] : []

  # Certificate region validation based on endpoint type
  certificate_region_errors = local.certificate_arn != null && local.certificate_region != local.required_region ? [
    "Certificate region mismatch: ${local.custom_domain_config.endpointType} endpoints require certificate in ${local.required_region}, got certificate in ${local.certificate_region}"
  ] : []

  # Hosted zone validation
  hosted_zone_errors = var.domain_config != null && !var.create_hosted_zone && try(var.domain_config.hostedZoneId, null) == null ? [
    "Route 53 hosted zone required. Provide customDomain.hostedZoneId or set create_hosted_zone=true."
  ] : []

  # Hosted zone ID format validation
  hosted_zone_format_errors = try(var.domain_config.hostedZoneId, null) != null && !can(regex("^Z[A-Z0-9]+$", var.domain_config.hostedZoneId)) ? [
    "Field 'customDomain.hostedZoneId' must match pattern 'Z[A-Z0-9]+'. Got: '${var.domain_config.hostedZoneId}'"
  ] : []

  # Collect all validation errors
  validation_errors = concat(
    local.required_field_errors,
    local.format_validation_errors,
    local.certificate_required_errors,
    local.certificate_format_errors,
    local.certificate_region_errors,
    local.endpoint_type_errors,
    local.hosted_zone_errors,
    local.hosted_zone_format_errors,
    local.base_path_errors
  )

  has_errors = length(local.validation_errors) > 0
}

# Validation enforcement via null_resource precondition
resource "null_resource" "custom_domain_validation" {
  lifecycle {
    precondition {
      condition     = !local.has_errors
      error_message = "Custom domain validation failed:\n- ${join("\n- ", local.validation_errors)}"
    }
  }
}
