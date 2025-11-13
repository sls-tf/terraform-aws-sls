module "serverless_parser" {
  source = "../.."

  config_path = "${path.module}/serverless.yml"
}

output "service_name" {
  value       = module.serverless_parser.parsed_config.service
  description = "The service name from serverless.yml"
}

output "provider_name" {
  value       = module.serverless_parser.parsed_config.provider.name
  description = "The provider name from serverless.yml"
}
