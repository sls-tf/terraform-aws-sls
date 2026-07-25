# ============================================================================
# EventBridge & CloudWatch Event Rules (Roadmap #7)
# ============================================================================

# CloudWatch Event Rules for schedule events
resource "aws_cloudwatch_event_rule" "schedule" {
  for_each = local.schedule_event_map

  name                = each.value.name != null ? each.value.name : "${try(local.parsed_config.service, "unknown")}-${local.provider_with_defaults.stage}-${each.value.function_name}-schedule-${each.value.event_index}"
  description         = each.value.description
  schedule_expression = each.value.schedule_expression
  state               = each.value.enabled ? "ENABLED" : "DISABLED"

  depends_on = [null_resource.config_validation]
}

# CloudWatch Event Rules for eventBridge events
resource "aws_cloudwatch_event_rule" "eventbridge" {
  for_each = local.eventbridge_event_map

  name           = "${try(local.parsed_config.service, "unknown")}-${local.provider_with_defaults.stage}-${each.value.function_name}-eventbridge-${each.value.event_index}"
  description    = each.value.description
  event_bus_name = each.value.eventBus
  event_pattern  = jsonencode(each.value.pattern)
  state          = each.value.enabled ? "ENABLED" : "DISABLED"

  depends_on = [null_resource.config_validation]
}

# CloudWatch Event Targets for schedule events
resource "aws_cloudwatch_event_target" "schedule" {
  for_each = local.schedule_event_map

  rule      = aws_cloudwatch_event_rule.schedule[each.key].name
  target_id = each.value.target_id != null ? each.value.target_id : "${each.value.function_name}-schedule-${each.value.event_index}"
  arn       = aws_lambda_function.functions[each.value.function_name].arn

  # Optional explicit retry policy (schedule.retryPolicy).
  dynamic "retry_policy" {
    for_each = each.value.retry_max_attempts != null || each.value.retry_max_event_age != null ? [1] : []
    content {
      maximum_retry_attempts       = each.value.retry_max_attempts
      maximum_event_age_in_seconds = each.value.retry_max_event_age
    }
  }

  # Input configuration (static, path, or transformer)
  input      = each.value.input != null ? jsonencode(each.value.input) : null
  input_path = each.value.inputPath

  dynamic "input_transformer" {
    for_each = each.value.inputTransformer != null ? [each.value.inputTransformer] : []
    content {
      input_paths    = try(input_transformer.value.inputPathsMap, null)
      input_template = try(input_transformer.value.inputTemplate, null)
    }
  }
}

# CloudWatch Event Targets for eventBridge events
resource "aws_cloudwatch_event_target" "eventbridge" {
  for_each = local.eventbridge_event_map

  rule           = aws_cloudwatch_event_rule.eventbridge[each.key].name
  event_bus_name = each.value.eventBus
  target_id      = "${each.value.function_name}-eventbridge-${each.value.event_index}"
  arn            = aws_lambda_function.functions[each.value.function_name].arn

  # Input configuration (static, path, or transformer)
  input      = each.value.input != null ? jsonencode(each.value.input) : null
  input_path = each.value.inputPath

  dynamic "input_transformer" {
    for_each = each.value.inputTransformer != null ? [each.value.inputTransformer] : []
    content {
      input_paths    = try(input_transformer.value.inputPathsMap, null)
      input_template = try(input_transformer.value.inputTemplate, null)
    }
  }
}

# Lambda permissions for schedule event rules
resource "aws_lambda_permission" "schedule_events" {
  for_each = local.schedule_event_map

  statement_id = each.value.permission_sid != null ? each.value.permission_sid : replace(replace(replace(replace(
    var.schedule_permission_sid_template,
    "{service}", try(local.parsed_config.service, "unknown")),
    "{stage}", local.provider_with_defaults.stage),
    "{function}", each.value.function_name),
    "{index}", tostring(each.value.event_index)
  )
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.functions[each.value.function_name].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule[each.key].arn
}

# Lambda permissions for eventBridge event rules
resource "aws_lambda_permission" "eventbridge_events" {
  for_each = local.eventbridge_event_map

  statement_id  = "${try(local.parsed_config.service, "unknown")}-${local.provider_with_defaults.stage}-${each.value.function_name}-eventbridge-${each.value.event_index}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.functions[each.value.function_name].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.eventbridge[each.key].arn
}
