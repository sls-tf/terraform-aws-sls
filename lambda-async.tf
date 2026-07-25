# ============================================================================
# Function-level async invoke config + DLQ
# ============================================================================
# The function's OWN async-invoke settings — distinct from any per-event-source
# DLQ (EventBridge target DLQ, SQS redrive):
#
#   dead_letter_config on aws_lambda_function     <- SAM `DeadLetterQueue:
#     {Type, TargetArn}` / serverless yaml `onError: <arn>`
#   aws_lambda_function_event_invoke_config       <- SAM `EventInvokeConfig:
#     {MaximumEventAgeInSeconds, MaximumRetryAttempts, DestinationConfig}` /
#     serverless yaml `maximumEventAge` / `maximumRetryAttempts` /
#     `destinations: {onSuccess, onFailure}`
#
# ARN references resolve to co-planned resources: {Ref}/{Fn::GetAtt} objects
# (yaml) or a SAM-preprocessor-fabricated ARN whose trailing name matches a
# template queue/topic map back to the created aws_sqs_queue/aws_sns_topic;
# literal external ARNs pass through.
#
# Presence booleans come from the plan-known parse (sam_structure for SAM, the
# raw yaml parse otherwise) so dynamic-block/for_each shapes stay plan-known.
# Functions with a module-created role also get the needed sqs:SendMessage /
# sns:Publish policy for their DLQ.

locals {
  # Created queue/topic NAME -> logical ID, mirroring the name fallbacks used at
  # creation, so a fabricated/resolved ARN maps back to the real resource.
  _sqs_queue_name_to_logical = {
    for lid in keys(local.sqs_queues) :
    tostring(try(local._custom_resources_structure[lid].Properties.QueueName, "${local.to_snake_case[lid]}-${local.provider_with_defaults.stage}")) => lid
  }
  _sns_topic_name_to_logical = {
    for lid in keys(local.sns_topics) :
    tostring(try(local._custom_resources_structure[lid].Properties.TopicName, "${local.to_snake_case[lid]}-${local.provider_with_defaults.stage}")) => lid
  }

  # AUTO-CREATED function DLQs: yaml `dlq: {enabled: true, name?: x}` or SAM
  # `DeadLetterQueue.QueueName` (extension — QueueName instead of TargetArn)
  # provision the queue themselves. Name defaults to "<function>-dlq".
  _function_auto_dlq_names = {
    for fn in local._function_names :
    fn => var.config_format == "sam" ? (
      tostring(try(local.sam_structure.Resources[fn].Properties.DeadLetterQueue.QueueName, ""))
      ) : (
      try(local.parsed_config.functions[fn].dlq.enabled, false) == true
      ? tostring(try(local.parsed_config.functions[fn].dlq.name, "${fn}-dlq"))
      : ""
    )
  }

  _function_auto_dlq = {
    for fn, name in local._function_auto_dlq_names :
    fn => name
    if name != ""
  }

  # Plan-known presence of a function-level DLQ (referenced or auto-created).
  _function_has_dlq = {
    for fn in local._function_names :
    fn => local._function_auto_dlq_names[fn] != "" || (
      var.config_format == "sam" ? (
        local.sam_structure != null && try(local.sam_structure.Resources[fn].Properties.DeadLetterQueue.TargetArn, null) != null
        ) : (
        try(local.parsed_config.functions[fn].onError, null) != null
      )
    )
  }

  # Plan-known presence of async event-invoke settings.
  _function_has_event_invoke = {
    for fn in local._function_names :
    fn => var.config_format == "sam" ? (
      local.sam_structure != null && try(local.sam_structure.Resources[fn].Properties.EventInvokeConfig, null) != null
      ) : (
      try(local.parsed_config.functions[fn].maximumEventAge, null) != null
      || try(local.parsed_config.functions[fn].maximumRetryAttempts, null) != null
      || try(local.parsed_config.functions[fn].destinations, null) != null
    )
  }

  # Normalized async config per function. Raw values keep their original shape
  # (string or Ref/GetAtt object); resolution to real ARNs happens at the
  # resource sites below.
  function_async_config = {
    for fn in local._function_names :
    fn => {
      # SAM shape first, serverless yaml shape as fallback.
      dlq_raw  = try(local.functions_with_defaults[fn].dead_letter_queue.target_arn, try(local.functions_with_defaults[fn].onError, null))
      dlq_type = upper(tostring(try(local.functions_with_defaults[fn].dead_letter_queue.type, "SQS")))

      maximum_event_age_in_seconds = try(
        local.functions_with_defaults[fn].event_invoke_config.maximum_event_age_in_seconds,
        try(local.functions_with_defaults[fn].maximumEventAge, null)
      )
      maximum_retry_attempts = try(
        local.functions_with_defaults[fn].event_invoke_config.maximum_retry_attempts,
        try(local.functions_with_defaults[fn].maximumRetryAttempts, null)
      )
      on_success_raw = try(local.functions_with_defaults[fn].event_invoke_config.on_success, try(local.functions_with_defaults[fn].destinations.onSuccess, null))
      on_failure_raw = try(local.functions_with_defaults[fn].event_invoke_config.on_failure, try(local.functions_with_defaults[fn].destinations.onFailure, null))
    }
  }

  # Resolved DLQ ARN per function-with-DLQ (used by both the function's
  # dead_letter_config and the IAM policy). Auto-created queues win.
  function_dlq_arns = {
    for fn in local._function_names :
    fn => contains(keys(local._function_auto_dlq), fn) ? aws_sqs_queue.function_dlq[fn].arn : try(
      aws_sqs_queue.custom[local.function_async_config[fn].dlq_raw.Ref].arn,
      aws_sqs_queue.custom[local.function_async_config[fn].dlq_raw["Fn::GetAtt"][0]].arn,
      aws_sns_topic.custom[local.function_async_config[fn].dlq_raw.Ref].arn,
      aws_sns_topic.custom[local.function_async_config[fn].dlq_raw["Fn::GetAtt"][0]].arn,
      aws_sqs_queue.custom[local._sqs_queue_name_to_logical[regex(":([^:]+)$", tostring(local.function_async_config[fn].dlq_raw))[0]]].arn,
      aws_sns_topic.custom[local._sns_topic_name_to_logical[regex(":([^:]+)$", tostring(local.function_async_config[fn].dlq_raw))[0]]].arn,
      tostring(local.function_async_config[fn].dlq_raw),
      ""
    )
    if local._function_has_dlq[fn]
  }
}

# Auto-created per-function DLQ (yaml dlq: {enabled, name} / SAM
# DeadLetterQueue.QueueName).
resource "aws_sqs_queue" "function_dlq" {
  for_each = local._function_auto_dlq

  name = each.value

  tags = {
    ManagedBy   = "sls.tf"
    Function    = each.key
    Environment = local.provider_with_defaults.stage
  }

  depends_on = [null_resource.config_validation]
}

# Async invoke settings (max age / retries / success+failure destinations).
resource "aws_lambda_function_event_invoke_config" "functions" {
  for_each = { for fn in local._function_names : fn => local.function_async_config[fn] if local._function_has_event_invoke[fn] }

  function_name = aws_lambda_function.functions[each.key].function_name

  maximum_event_age_in_seconds = each.value.maximum_event_age_in_seconds
  maximum_retry_attempts       = each.value.maximum_retry_attempts

  dynamic "destination_config" {
    for_each = each.value.on_success_raw != null || each.value.on_failure_raw != null ? [1] : []
    content {
      dynamic "on_success" {
        for_each = each.value.on_success_raw != null ? [each.value.on_success_raw] : []
        content {
          destination = try(
            aws_sqs_queue.custom[on_success.value.Ref].arn,
            aws_sqs_queue.custom[on_success.value["Fn::GetAtt"][0]].arn,
            aws_sns_topic.custom[on_success.value.Ref].arn,
            aws_sns_topic.custom[on_success.value["Fn::GetAtt"][0]].arn,
            aws_sqs_queue.custom[local._sqs_queue_name_to_logical[regex(":([^:]+)$", tostring(on_success.value))[0]]].arn,
            aws_sns_topic.custom[local._sns_topic_name_to_logical[regex(":([^:]+)$", tostring(on_success.value))[0]]].arn,
            tostring(on_success.value)
          )
        }
      }
      dynamic "on_failure" {
        for_each = each.value.on_failure_raw != null ? [each.value.on_failure_raw] : []
        content {
          destination = try(
            aws_sqs_queue.custom[on_failure.value.Ref].arn,
            aws_sqs_queue.custom[on_failure.value["Fn::GetAtt"][0]].arn,
            aws_sns_topic.custom[on_failure.value.Ref].arn,
            aws_sns_topic.custom[on_failure.value["Fn::GetAtt"][0]].arn,
            aws_sqs_queue.custom[local._sqs_queue_name_to_logical[regex(":([^:]+)$", tostring(on_failure.value))[0]]].arn,
            aws_sns_topic.custom[local._sns_topic_name_to_logical[regex(":([^:]+)$", tostring(on_failure.value))[0]]].arn,
            tostring(on_failure.value)
          )
        }
      }
    }
  }

  depends_on = [null_resource.config_validation]
}

# Let the module-created execution role deliver to the function's DLQ. A
# function with an explicit external Role is assumed to bring its own policy.
resource "aws_iam_role_policy" "lambda_dlq" {
  for_each = {
    for fn, arn in local.function_dlq_arns :
    fn => arn
    if !try(local._function_has_explicit_role[fn], false)
  }

  name = "dlq-access"
  role = aws_iam_role.lambda_execution[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      # The DLQ is either SQS or SNS; the wrong-service action on a specific
      # ARN is inert, so granting both keeps this type-agnostic.
      Action   = ["sqs:SendMessage", "sns:Publish"]
      Resource = each.value
    }]
  })
}
