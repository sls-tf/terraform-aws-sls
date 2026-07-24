# ============================================================================
# Centrally-declared multi-target EventBridge rules (AWS::Events::Rule)
# ============================================================================
# A function's own eventBridge event creates one rule with that function as its
# single implicit target. This file covers the other shape: rules declared
# centrally in the resources: section, each with an arbitrary event pattern and
# a LIST of independently-configured targets (lambda target, per-target DLQ,
# per-target retry policy) so multiple targets can share one rule.
#
# Reference resolution per target:
#   Arn              — !GetAtt Fn.Arn / {Fn::GetAtt: [Fn, Arn]} / {Ref: Fn} /
#                      resolved ":function:<name>" ARN -> function logical ID ->
#                      aws_lambda_function.functions[<id>]. Non-function ARNs
#                      pass through as literals.
#   DeadLetterConfig — {Fn::GetAtt: [Queue, Arn]} to a template AWS::SQS::Queue
#                      resolves to the created queue's ARN; literals pass through.
#
# for_each keys (rule logical ID, target index) come from the STRUCTURAL parse
# so they stay plan-known on greenfield.

locals {
  events_rules = {
    for logical_id, resource in local._custom_resources_structure :
    logical_id => resource
    if try(resource.Type, "") == "AWS::Events::Rule"
    && (contains(coalesce(var.resource_types, ["AWS::Events::Rule"]), "AWS::Events::Rule"))
  }

  # Flattened "<ruleLogicalId>-<index>" -> target config. Structure (keys,
  # count) from the structural parse; values from the resolved parse.
  events_rule_targets = {
    for pair in flatten([
      for rule_id in keys(local.events_rules) : [
        for idx, structural_target in try(local._custom_resources_structure[rule_id].Properties.Targets, []) : {
          key       = "${rule_id}-${idx}"
          rule_id   = rule_id
          target    = try(local.custom_resources_raw[rule_id].Properties.Targets[idx], {})
          target_id = tostring(try(structural_target.Id, "target-${idx}"))
          # Function logical ID when the target ARN references a template
          # function; "" for non-function targets.
          function_id = try(
            local._function_name_to_logical[regex("function:([^/:]+)", tostring(try(structural_target.Arn, "")))[0]],
            local._function_name_to_logical[try(structural_target.Arn["Fn::GetAtt"][0], "")],
            local._function_name_to_logical[try(structural_target.Arn.Ref, "")],
            ""
          )
        }
      ]
    ]) : pair.key => pair
  }

  # Targets that resolve to a template Lambda function need an invoke permission.
  events_rule_lambda_targets = {
    for key, target in local.events_rule_targets :
    key => target
    if target.function_id != ""
  }
}

resource "aws_cloudwatch_event_rule" "cfn" {
  for_each = local.events_rules

  name = try(
    local.custom_resources_raw[each.key].Properties.Name,
    "${local.to_snake_case[each.key]}-${local.provider_with_defaults.stage}"
  )
  description = try(local.custom_resources_raw[each.key].Properties.Description, null)

  # EventPattern is an object in templates; the provider wants JSON.
  event_pattern = try(local.custom_resources_raw[each.key].Properties.EventPattern, null) != null ? try(
    tostring(local.custom_resources_raw[each.key].Properties.EventPattern),
    jsonencode(local.custom_resources_raw[each.key].Properties.EventPattern)
  ) : null
  schedule_expression = try(local.custom_resources_raw[each.key].Properties.ScheduleExpression, null)

  event_bus_name = try(local.custom_resources_raw[each.key].Properties.EventBusName, "default")
  state          = try(local.custom_resources_raw[each.key].Properties.State, "ENABLED")

  tags = {
    Name        = each.key
    ManagedBy   = "sls.tf"
    LogicalId   = each.key
    Environment = local.provider_with_defaults.stage
  }

  depends_on = [null_resource.config_validation]
}

resource "aws_cloudwatch_event_target" "cfn" {
  for_each = local.events_rule_targets

  rule           = aws_cloudwatch_event_rule.cfn[each.value.rule_id].name
  event_bus_name = aws_cloudwatch_event_rule.cfn[each.value.rule_id].event_bus_name
  target_id      = each.value.target_id

  # Template function target -> created function ARN; anything else literal.
  arn = each.value.function_id != "" ? aws_lambda_function.functions[each.value.function_id].arn : tostring(try(each.value.target.Arn, ""))

  # Input is a JSON string in CFN; accept a decoded object too.
  input = try(each.value.target.Input, null) != null ? try(
    tostring(each.value.target.Input),
    jsonencode(each.value.target.Input)
  ) : null
  input_path = try(each.value.target.InputPath, null)

  dynamic "input_transformer" {
    for_each = try(each.value.target.InputTransformer, null) != null ? [each.value.target.InputTransformer] : []
    content {
      input_paths    = try(input_transformer.value.InputPathsMap, null)
      input_template = input_transformer.value.InputTemplate
    }
  }

  # Per-target DLQ: {Fn::GetAtt: [Queue, Arn]} to a template queue, or literal.
  dynamic "dead_letter_config" {
    for_each = try(each.value.target.DeadLetterConfig.Arn, null) != null ? [each.value.target.DeadLetterConfig.Arn] : []
    content {
      arn = try(
        aws_sqs_queue.custom[dead_letter_config.value["Fn::GetAtt"][0]].arn,
        aws_sqs_queue.custom[dead_letter_config.value.Ref].arn,
        tostring(dead_letter_config.value)
      )
    }
  }

  # Per-target retry policy.
  dynamic "retry_policy" {
    for_each = try(each.value.target.RetryPolicy, null) != null ? [each.value.target.RetryPolicy] : []
    content {
      maximum_event_age_in_seconds = try(retry_policy.value.MaximumEventAgeInSeconds, null)
      maximum_retry_attempts       = try(retry_policy.value.MaximumRetryAttempts, null)
    }
  }

  depends_on = [null_resource.config_validation]
}

# Allow EventBridge to invoke each Lambda target.
resource "aws_lambda_permission" "cfn_events_rule" {
  for_each = local.events_rule_lambda_targets

  statement_id  = "AllowEventsRuleInvoke-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.functions[each.value.function_id].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cfn[each.value.rule_id].arn
}
