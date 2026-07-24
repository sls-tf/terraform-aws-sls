# ============================================================================
# CloudWatch observability + alerting
# ============================================================================
# Maps from the resources: section:
#   AWS::CloudWatch::Dashboard -> aws_cloudwatch_dashboard
#   AWS::CloudWatch::Alarm     -> aws_cloudwatch_metric_alarm (incl. alarm/OK/
#                                 insufficient-data actions; an action that
#                                 references a template AWS::SNS::Topic via Ref
#                                 resolves to the created topic's ARN)
#   AWS::SNS::Subscription     -> aws_sns_topic_subscription (https endpoints
#                                 cover PagerDuty-style integrations)

locals {
  # Resolve a CFN alarm action to an ARN. Handled forms, in order:
  #   {Ref = "TopicLogicalId"}          (yaml parse keeps the object)
  #   "__UNRESOLVED__!Ref Topic..."     (SAM preprocessor marker)
  #   literal ARN string
  # Implemented inline via try() chains below; this map precomputes the
  # per-alarm resolved action lists.
  cloudwatch_alarm_actions = {
    for logical_id, resource in local.cloudwatch_alarms :
    logical_id => {
      alarm_actions = [
        for action in try(resource.Properties.AlarmActions, []) :
        try(
          aws_sns_topic.custom[action.Ref].arn,
          aws_sns_topic.custom[replace(tostring(action), local._unresolved_ref_prefix, "")].arn,
          tostring(action)
        )
      ]
      ok_actions = [
        for action in try(resource.Properties.OKActions, []) :
        try(
          aws_sns_topic.custom[action.Ref].arn,
          aws_sns_topic.custom[replace(tostring(action), local._unresolved_ref_prefix, "")].arn,
          tostring(action)
        )
      ]
      insufficient_data_actions = [
        for action in try(resource.Properties.InsufficientDataActions, []) :
        try(
          aws_sns_topic.custom[action.Ref].arn,
          aws_sns_topic.custom[replace(tostring(action), local._unresolved_ref_prefix, "")].arn,
          tostring(action)
        )
      ]
    }
  }
}

resource "aws_cloudwatch_dashboard" "custom" {
  for_each = local.cloudwatch_dashboards

  dashboard_name = try(
    each.value.Properties.DashboardName,
    "${local.to_snake_case[each.key]}-${local.provider_with_defaults.stage}"
  )

  # DashboardBody is a JSON string in CFN; accept an already-decoded object too
  # (natural in yaml configs) and encode it.
  dashboard_body = try(
    tostring(each.value.Properties.DashboardBody),
    jsonencode(try(each.value.Properties.DashboardBody, {}))
  )

  depends_on = [null_resource.config_validation]
}

resource "aws_cloudwatch_metric_alarm" "custom" {
  for_each = local.cloudwatch_alarms

  alarm_name = try(
    each.value.Properties.AlarmName,
    "${local.to_snake_case[each.key]}-${local.provider_with_defaults.stage}"
  )
  alarm_description = try(each.value.Properties.AlarmDescription, null)

  comparison_operator = each.value.Properties.ComparisonOperator
  evaluation_periods  = each.value.Properties.EvaluationPeriods
  datapoints_to_alarm = try(each.value.Properties.DatapointsToAlarm, null)
  threshold           = try(each.value.Properties.Threshold, null)
  treat_missing_data  = try(each.value.Properties.TreatMissingData, "missing")

  metric_name        = try(each.value.Properties.MetricName, null)
  namespace          = try(each.value.Properties.Namespace, null)
  period             = try(each.value.Properties.Period, null)
  statistic          = try(each.value.Properties.Statistic, null)
  extended_statistic = try(each.value.Properties.ExtendedStatistic, null)
  unit               = try(each.value.Properties.Unit, null)

  # CFN dimension list [{Name, Value}] -> map. A Value that references a
  # template resource via Ref resolves to that resource's name.
  dimensions = {
    for dim in try(each.value.Properties.Dimensions, []) :
    dim.Name => try(
      aws_dynamodb_table.custom[dim.Value.Ref].name,
      aws_sqs_queue.custom[dim.Value.Ref].name,
      aws_lambda_function.functions[dim.Value.Ref].function_name,
      tostring(dim.Value)
    )
  }

  actions_enabled           = try(each.value.Properties.ActionsEnabled, true)
  alarm_actions             = local.cloudwatch_alarm_actions[each.key].alarm_actions
  ok_actions                = local.cloudwatch_alarm_actions[each.key].ok_actions
  insufficient_data_actions = local.cloudwatch_alarm_actions[each.key].insufficient_data_actions

  tags = merge(
    {
      Name        = each.key
      ManagedBy   = "sls.tf"
      LogicalId   = each.key
      Environment = local.provider_with_defaults.stage
    },
    try({
      for tag in each.value.Properties.Tags :
      tag.Key => tag.Value
    }, {})
  )

  depends_on = [null_resource.config_validation]
}

resource "aws_sns_topic_subscription" "custom" {
  for_each = local.sns_subscriptions

  # TopicArn may reference a template AWS::SNS::Topic via Ref, arrive as a SAM
  # marker, or be a literal ARN of an external topic.
  topic_arn = try(
    aws_sns_topic.custom[each.value.Properties.TopicArn.Ref].arn,
    aws_sns_topic.custom[replace(tostring(each.value.Properties.TopicArn), local._unresolved_ref_prefix, "")].arn,
    tostring(each.value.Properties.TopicArn)
  )

  protocol = each.value.Properties.Protocol
  endpoint = tostring(each.value.Properties.Endpoint)

  raw_message_delivery = try(each.value.Properties.RawMessageDelivery, false)

  # FilterPolicy is a JSON string in CFN; accept a decoded object too.
  filter_policy = try(each.value.Properties.FilterPolicy, null) != null ? try(
    tostring(each.value.Properties.FilterPolicy),
    jsonencode(each.value.Properties.FilterPolicy)
  ) : null
  filter_policy_scope = try(each.value.Properties.FilterPolicyScope, null)

  depends_on = [null_resource.config_validation]
}
