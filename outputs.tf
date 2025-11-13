output "parsed_config" {
  description = "Complete parsed Serverless Framework configuration object"
  value       = local.parsed_config
}

output "service_name" {
  description = "Service name extracted from configuration"
  value       = try(local.parsed_config.service, null)
}

output "provider_config" {
  description = "Provider configuration with defaults applied"
  value       = local.provider_with_defaults
}

output "functions" {
  description = "Map of function definitions with defaults applied"
  value       = local.functions_with_defaults
}

output "custom" {
  description = "Custom configuration section from serverless.yml"
  value       = try(local.parsed_config.custom, null)
}

output "resources" {
  description = "Resources section for custom AWS resources"
  value       = try(local.resolved_config.resources, null)
}

output "package" {
  description = "Packaging configuration section"
  value       = try(local.parsed_config.package, null)
}

output "lambda_packages" {
  description = "Lambda deployment package information (file paths and sizes)"
  value = {
    for key, archive in data.archive_file.lambda_code :
    key => {
      output_path      = archive.output_path
      output_size      = archive.output_size
      output_size_mb   = floor(archive.output_size / 1048576 * 100) / 100 # MB with 2 decimal places
      output_sha256    = archive.output_base64sha256
      within_aws_limit = archive.output_size <= 52428800 # 50 MB
    }
  }
}

output "function_arns" {
  description = "Map of Lambda function ARNs keyed by function name"
  value       = { for k, v in aws_lambda_function.functions : k => v.arn }
}

output "function_names" {
  description = "Map of Lambda function names keyed by function name"
  value       = { for k, v in aws_lambda_function.functions : k => v.function_name }
}

output "role_arns" {
  description = "Map of IAM role ARNs keyed by function name"
  value       = { for k, v in aws_iam_role.lambda_execution : k => v.arn }
}

output "function_invoke_arns" {
  description = "Map of Lambda function invoke ARNs for API Gateway integration"
  value       = { for k, v in aws_lambda_function.functions : k => v.invoke_arn }
}

output "policy_arns" {
  description = "Map of IAM custom policy ARNs keyed by function name (Roadmap #3)"
  value       = { for k, v in aws_iam_role_policy.lambda_custom_policy : k => v.id }
}

output "policy_names" {
  description = "Map of IAM custom policy names keyed by function name (Roadmap #3)"
  value       = { for k, v in aws_iam_role_policy.lambda_custom_policy : k => v.name }
}

# ============================================================================
# API Gateway Outputs (Roadmap #4)
# ============================================================================

output "api_gateway_rest_api_id" {
  description = "REST API ID for the API Gateway (null if no HTTP events)"
  value       = length(aws_api_gateway_rest_api.this) > 0 ? aws_api_gateway_rest_api.this[0].id : null
}

output "api_gateway_invoke_url" {
  description = "Invoke URL for the API Gateway stage (null if no HTTP events)"
  value       = length(aws_api_gateway_stage.this) > 0 ? aws_api_gateway_stage.this[0].invoke_url : null
}

output "api_gateway_stage_name" {
  description = "API Gateway stage name (null if no HTTP events)"
  value       = length(aws_api_gateway_stage.this) > 0 ? aws_api_gateway_stage.this[0].stage_name : null
}

output "api_gateway_resources" {
  description = "Map of API Gateway resource IDs by path (null if no HTTP events)"
  value       = length(local.http_events) > 0 ? { for k, v in local.all_api_resources : k => v.id } : null
}

# ============================================================================
# S3 Event Source Mapping Outputs (Roadmap #5)
# ============================================================================

output "s3_bucket_arns" {
  description = "Map of S3 bucket ARNs by bucket name"
  value = merge(
    { for k, v in aws_s3_bucket.event_buckets : k => v.arn },
    # Include existing buckets with constructed ARNs
    {
      for evt in local.s3_events_normalized :
      evt.bucket_name => "arn:aws:s3:::${evt.bucket_name}"
      if evt.existing
    }
  )
}

output "s3_bucket_names" {
  description = "Map of S3 bucket names by bucket key"
  value = {
    for evt in local.s3_events_normalized :
    evt.bucket_key => evt.bucket_name...
  }
}

output "s3_notification_ids" {
  description = "Map of S3 bucket notification IDs by bucket name"
  value       = { for k, v in aws_s3_bucket_notification.lambda_triggers : k => v.id }
}

# Event Source Mapping Outputs (Roadmap #8)
output "event_source_mapping_ids" {
  description = "Map of event source mapping IDs keyed by resource identifier"
  value       = { for k, v in aws_lambda_event_source_mapping.event_sources : k => v.id }
}

output "event_source_mapping_arns" {
  description = "Map of event source mapping ARNs keyed by resource identifier"
  value       = { for k, v in aws_lambda_event_source_mapping.event_sources : k => v.function_arn }
}

output "event_source_mapping_states" {
  description = "Map of event source mapping states keyed by resource identifier"
  value       = { for k, v in aws_lambda_event_source_mapping.event_sources : k => v.state }
}

output "event_source_mapping_count" {
  description = "Total count of event source mappings created"
  value       = length(aws_lambda_event_source_mapping.event_sources)
}

# ============================================================================
# EventBridge & CloudWatch Event Rule Outputs (Roadmap #7)
# ============================================================================

output "schedule_rule_arns" {
  description = "Map of schedule event rule ARNs keyed by event key"
  value       = { for k, v in aws_cloudwatch_event_rule.schedule : k => v.arn }
}

output "schedule_rule_names" {
  description = "Map of schedule event rule names keyed by event key"
  value       = { for k, v in aws_cloudwatch_event_rule.schedule : k => v.name }
}

output "eventbridge_rule_arns" {
  description = "Map of eventBridge rule ARNs keyed by event key"
  value       = { for k, v in aws_cloudwatch_event_rule.eventbridge : k => v.arn }
}

output "eventbridge_rule_names" {
  description = "Map of eventBridge rule names keyed by event key"
  value       = { for k, v in aws_cloudwatch_event_rule.eventbridge : k => v.name }
}

output "schedule_event_count" {
  description = "Total count of schedule event rules created"
  value       = length(aws_cloudwatch_event_rule.schedule)
}

output "eventbridge_event_count" {
  description = "Total count of eventBridge rules created"
  value       = length(aws_cloudwatch_event_rule.eventbridge)
}

# ============================================================================
# Custom Resource Outputs (Roadmap #9)
# ============================================================================

output "custom_s3_bucket_ids" {
  description = "Map of custom S3 bucket IDs keyed by logical ID"
  value       = { for k, v in aws_s3_bucket.custom : k => v.id }
}

output "custom_s3_bucket_arns" {
  description = "Map of custom S3 bucket ARNs keyed by logical ID"
  value       = { for k, v in aws_s3_bucket.custom : k => v.arn }
}

output "custom_dynamodb_table_names" {
  description = "Map of custom DynamoDB table names keyed by logical ID"
  value       = { for k, v in aws_dynamodb_table.custom : k => v.name }
}

output "custom_dynamodb_table_arns" {
  description = "Map of custom DynamoDB table ARNs keyed by logical ID"
  value       = { for k, v in aws_dynamodb_table.custom : k => v.arn }
}

output "custom_sns_topic_names" {
  description = "Map of custom SNS topic names keyed by logical ID"
  value       = { for k, v in aws_sns_topic.custom : k => v.name }
}

output "custom_sns_topic_arns" {
  description = "Map of custom SNS topic ARNs keyed by logical ID"
  value       = { for k, v in aws_sns_topic.custom : k => v.arn }
}

output "custom_sqs_queue_names" {
  description = "Map of custom SQS queue names keyed by logical ID"
  value       = { for k, v in aws_sqs_queue.custom : k => v.name }
}

output "custom_sqs_queue_arns" {
  description = "Map of custom SQS queue ARNs keyed by logical ID"
  value       = { for k, v in aws_sqs_queue.custom : k => v.arn }
}

output "custom_sqs_queue_urls" {
  description = "Map of custom SQS queue URLs keyed by logical ID"
  value       = { for k, v in aws_sqs_queue.custom : k => v.url }
}

output "custom_resources_count" {
  description = "Total count of custom resources created"
  value = {
    s3_buckets               = length(aws_s3_bucket.custom)
    dynamodb_tables          = length(aws_dynamodb_table.custom)
    sns_topics               = length(aws_sns_topic.custom)
    sqs_queues               = length(aws_sqs_queue.custom)
    cloudfront_distributions = length(aws_cloudfront_distribution.custom)
  }
}

# CloudFront Distribution outputs (Roadmap #12)
output "custom_cloudfront_distribution_ids" {
  description = "Map of custom CloudFront distribution IDs keyed by logical ID"
  value       = { for k, v in aws_cloudfront_distribution.custom : k => v.id }
}

output "custom_cloudfront_distribution_arns" {
  description = "Map of custom CloudFront distribution ARNs keyed by logical ID"
  value       = { for k, v in aws_cloudfront_distribution.custom : k => v.arn }
}

output "custom_cloudfront_distribution_domain_names" {
  description = "Map of custom CloudFront distribution domain names keyed by logical ID"
  value       = { for k, v in aws_cloudfront_distribution.custom : k => v.domain_name }
}

output "custom_cloudfront_distribution_hosted_zone_ids" {
  description = "Map of custom CloudFront distribution hosted zone IDs keyed by logical ID"
  value       = { for k, v in aws_cloudfront_distribution.custom : k => v.hosted_zone_id }
}
