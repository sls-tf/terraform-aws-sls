output "function_arns" {
  description = "Lambda function ARNs"
  value       = module.serverless.function_arns
}

output "function_names" {
  description = "Lambda function names"
  value       = module.serverless.function_names
}

output "role_arns" {
  description = "IAM role ARNs"
  value       = module.serverless.role_arns
}

output "function_invoke_arns" {
  description = "Lambda function invoke ARNs for API Gateway"
  value       = module.serverless.function_invoke_arns
}

output "lambda_packages" {
  description = "Lambda deployment package information"
  value       = module.serverless.lambda_packages
}
