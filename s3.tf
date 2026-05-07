# S3 Event Source Mapping Resources
# Handles S3 bucket creation, Lambda permissions, and S3 bucket notifications

# Create new S3 buckets (only for non-existing bucket references)
resource "aws_s3_bucket" "event_buckets" {
  for_each = local.s3_buckets_to_create

  bucket = each.value.name

  # Additional properties from provider.s3 section applied via lifecycle configuration
  # versioningConfiguration, etc. handled by separate aws_s3_bucket_versioning resources

  depends_on = [null_resource.config_validation]
}

# Lambda permissions for S3 invocation
resource "aws_lambda_permission" "s3_triggers" {
  for_each = {
    for evt in local.s3_events_normalized :
    "${evt.function_name}-${evt.bucket_name}" => evt
  }

  statement_id  = "AllowExecutionFromS3-${each.value.bucket_name}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.functions[each.value.function_name].function_name
  principal     = "s3.amazonaws.com"
  source_arn    = each.value.existing ? "arn:aws:s3:::${each.value.bucket_name}" : aws_s3_bucket.event_buckets[each.value.bucket_key].arn

  depends_on = [null_resource.config_validation]
}

# S3 bucket notifications (aggregated - one per bucket)
resource "aws_s3_bucket_notification" "lambda_triggers" {
  for_each = local.s3_notifications_aggregated

  bucket = each.key

  dynamic "lambda_function" {
    for_each = each.value
    content {
      lambda_function_arn = aws_lambda_function.functions[lambda_function.value.function_name].arn
      events              = lambda_function.value.events
      filter_prefix       = lambda_function.value.filter_prefix
      filter_suffix       = lambda_function.value.filter_suffix
    }
  }

  depends_on = [aws_lambda_permission.s3_triggers]
}
