output "custom_domain_name" {
  description = "The custom domain name configured, or null if not configured"
  value       = var.domain_config != null ? aws_api_gateway_domain_name.custom_domain.domain_name : null
}

output "custom_domain_target" {
  description = "CloudFront or regional endpoint DNS target for manual DNS setup"
  value       = var.domain_config != null ? local.domain_name_target : null
}

output "custom_domain_hosted_zone_id" {
  description = "Route 53 hosted zone ID used for DNS records"
  value       = var.domain_config != null ? local.hosted_zone_id : null
}

output "custom_domain_base_path" {
  description = "Base path mapping configured for the domain, or null"
  value       = var.domain_config != null ? try(var.domain_config.basePath, null) : null
}

output "route53_record_fqdn" {
  description = "Fully qualified domain name of created Route 53 record, or null if not created"
  value       = var.domain_config != null && try(local.custom_domain_config.createRoute53Record, true) ? try(aws_route53_record.custom_domain[0].fqdn, null) : null
}

output "api_gateway_domain_name_id" {
  description = "API Gateway domain name resource ID for external references"
  value       = var.domain_config != null ? aws_api_gateway_domain_name.custom_domain.id : null
}
