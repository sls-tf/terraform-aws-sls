# Event Source Mapping Resources (Roadmap #8)
# DynamoDB Streams and SQS Queue event source mappings for Lambda functions

resource "aws_lambda_event_source_mapping" "event_sources" {
  for_each = local.event_source_mappings

  function_name    = aws_lambda_function.functions[each.value.function_name].function_name
  event_source_arn = each.value.arn
  enabled          = try(each.value.event_config.enabled, true)
  batch_size       = try(each.value.event_config.batchSize, each.value.type == "stream" ? 100 : 10)

  # DynamoDB Stream specific settings
  starting_position              = each.value.type == "stream" ? try(each.value.event_config.startingPosition, "TRIM_HORIZON") : null
  parallelization_factor         = each.value.type == "stream" ? try(each.value.event_config.parallelizationFactor, null) : null
  maximum_record_age_in_seconds  = each.value.type == "stream" ? try(each.value.event_config.maximumRecordAgeInSeconds, null) : null
  bisect_batch_on_function_error = each.value.type == "stream" ? try(each.value.event_config.bisectBatchOnFunctionError, null) : null
  tumbling_window_in_seconds     = each.value.type == "stream" ? try(each.value.event_config.tumblingWindowInSeconds, null) : null

  # SQS specific settings
  dynamic "scaling_config" {
    for_each = each.value.type == "sqs" && try(each.value.event_config.scalingConfig, null) != null ? [each.value.event_config.scalingConfig] : []
    content {
      maximum_concurrency = try(scaling_config.value.maximumConcurrency, null)
    }
  }

  function_response_types = each.value.type == "sqs" ? try(each.value.event_config.functionResponseTypes, null) : null

  # Common settings
  maximum_batching_window_in_seconds = try(each.value.event_config.maximumBatchingWindowInSeconds, null)
  maximum_retry_attempts             = try(each.value.event_config.maximumRetryAttempts, null)

  # Destination config for failures
  dynamic "destination_config" {
    for_each = try(each.value.event_config.destinationConfig, null) != null ? [each.value.event_config.destinationConfig] : []
    content {
      on_failure {
        destination_arn = destination_config.value.onFailure.destination
      }
    }
  }

  # Filter criteria
  dynamic "filter_criteria" {
    for_each = try(each.value.event_config.filterPatterns, null) != null ? [1] : []
    content {
      dynamic "filter" {
        for_each = try(each.value.event_config.filterPatterns, [])
        content {
          pattern = jsonencode(filter.value)
        }
      }
    }
  }

  depends_on = [null_resource.config_validation]
}
