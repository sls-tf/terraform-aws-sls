output "parsed_service_name" {
  description = "Service name from serverless.yml"
  value       = module.serverless_parser.service_name
}

output "provider_with_defaults" {
  description = "Provider configuration with all defaults applied"
  value       = module.serverless_parser.provider_config
}

output "functions_with_defaults" {
  description = "Functions with inherited defaults"
  value       = module.serverless_parser.functions
}

output "custom_config" {
  description = "Custom configuration section"
  value       = module.serverless_parser.custom
}

output "resources_config" {
  description = "Resources section"
  value       = module.serverless_parser.resources
}
