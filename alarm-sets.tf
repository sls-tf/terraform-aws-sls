# ============================================================================
# Dynamic alarm sets — batch alarms over module-derived resources
# ============================================================================
# One AWS::CloudWatch::Alarm per resource works for a fixed list, but consumers
# commonly want "one alarm per lambda/table/queue, whatever that set turns out
# to be" without hand-enumerating (and hand-maintaining) every alarm. This adds
# a templated construct:
#
#   yaml (top level):            SAM (template Metadata):
#     alarms:                      Metadata:
#       defaults:                    SlsTf:
#         actions: [...]               Alarms:
#       groups:                          defaults: {...}
#         lambda:                        groups: {...}
#           resource_names: []   # empty/omitted = ALL created resources of the class
#           metrics:
#             - name: Errors
#               period: 300
#               statistic: Sum
#               threshold: 5
#               comparisonOperator: GreaterThanOrEqualToThreshold
#               evaluationPeriods: 2        # optional, default 1
#               treatMissingData: notBreaching   # optional
#
# Known classes (lambda, dynamodb, sqs, sns, s3, eventbridge, athena,
# api_gateway) get a default namespace + dimension name and — except
# api_gateway — auto-enumeration of the created resources' names. A group may
# override `namespace`/`dimension`, and any class can pin `resource_names`
# explicitly. `actions` (group-level, falling back to defaults.actions) accepts
# literal ARNs or Refs to template SNS topics.
#
# One alarm is created per (group, metric, resource): key
# "<group>-<metric>-<resource>", which is also the alarm name — so alarms track
# the resource set as functions/tables are added or removed.

locals {
  # JSON-laundered (same idiom as parsed_config) so the two branches don't need
  # structurally identical object types.
  alarm_sets_config = jsondecode(
    var.config_format == "sam"
    ? jsonencode(local.sam_structure != null ? try(local.sam_structure.Metadata.SlsTf.Alarms, {}) : {})
    : jsonencode(try(local.parsed_config.alarms, {}))
  )

  _alarm_class_defaults = {
    lambda      = { namespace = "AWS/Lambda", dimension = "FunctionName" }
    dynamodb    = { namespace = "AWS/DynamoDB", dimension = "TableName" }
    sqs         = { namespace = "AWS/SQS", dimension = "QueueName" }
    sns         = { namespace = "AWS/SNS", dimension = "TopicName" }
    s3          = { namespace = "AWS/S3", dimension = "BucketName" }
    eventbridge = { namespace = "AWS/Events", dimension = "RuleName" }
    athena      = { namespace = "AWS/Athena", dimension = "WorkGroup" }
    api_gateway = { namespace = "AWS/ApiGateway", dimension = "ApiName" }
  }

  # All created resource names per class, mirroring each resource's own naming
  # fallback, from plan-known (structural) sources — these names become
  # for_each keys.
  _alarm_class_all_names = {
    lambda = [
      for fn in local._function_names :
      try(local.functions_with_defaults[fn].name, null) != null ? tostring(local.functions_with_defaults[fn].name) : "${try(local.parsed_config_resolved.service, "unknown")}-${local.provider_with_defaults.stage}-${fn}"
    ]
    dynamodb = [
      for lid in keys(local.dynamodb_tables) :
      tostring(try(local._custom_resources_structure[lid].Properties.TableName, "${local.to_snake_case[lid]}-${local.provider_with_defaults.stage}"))
    ]
    sqs = keys(local._sqs_queue_name_to_logical)
    sns = keys(local._sns_topic_name_to_logical)
    s3 = [
      for lid in keys(local.s3_buckets) :
      tostring(try(local._custom_resources_structure[lid].Properties.BucketName, "${local.to_snake_case[lid]}-${local.provider_with_defaults.stage}"))
    ]
    eventbridge = [
      for lid in keys(local.events_rules) :
      tostring(try(local._custom_resources_structure[lid].Properties.Name, "${local.to_snake_case[lid]}-${local.provider_with_defaults.stage}"))
    ]
    athena = [
      for lid in keys(local.athena_workgroups) :
      tostring(try(local._custom_resources_structure[lid].Properties.Name, "${local.to_snake_case[lid]}-${local.provider_with_defaults.stage}"))
    ]
    # No reliable auto-enumeration (an API name isn't always module-derived);
    # declare resource_names explicitly for this class.
    api_gateway = []
  }

  # (group, metric, resource) -> alarm spec.
  alarm_set_alarms = {
    for spec in flatten([
      for group_name, group in try(local.alarm_sets_config.groups, {}) : [
        for metric in try(group.metrics, []) : [
          for resource_name in(
            length(try(group.resource_names, [])) > 0
            ? [for r in group.resource_names : tostring(r)]
            : try(local._alarm_class_all_names[group_name], [])
            ) : {
            key           = "${group_name}-${metric.name}-${resource_name}"
            namespace     = tostring(try(group.namespace, try(local._alarm_class_defaults[group_name].namespace, "")))
            dimension     = tostring(try(group.dimension, try(local._alarm_class_defaults[group_name].dimension, "")))
            resource_name = resource_name
            metric        = metric
            actions       = try(group.actions, try(local.alarm_sets_config.defaults.actions, []))
          }
        ]
      ]
    ]) : spec.key => spec
  }
}

resource "aws_cloudwatch_metric_alarm" "set" {
  for_each = local.alarm_set_alarms

  alarm_name        = each.key
  alarm_description = try(each.value.metric.description, "Managed by sls.tf alarm set")

  namespace   = each.value.namespace
  metric_name = each.value.metric.name
  dimensions  = { (each.value.dimension) = each.value.resource_name }

  comparison_operator = each.value.metric.comparisonOperator
  threshold           = each.value.metric.threshold
  period              = try(each.value.metric.period, 300)
  statistic           = try(each.value.metric.statistic, "Sum")
  evaluation_periods  = try(each.value.metric.evaluationPeriods, 1)
  datapoints_to_alarm = try(each.value.metric.datapointsToAlarm, null)
  treat_missing_data  = try(each.value.metric.treatMissingData, "missing")

  alarm_actions = [
    for action in each.value.actions :
    try(
      local._sns_topic_ref_arns[action.Ref],
      local._sns_topic_ref_arns[replace(tostring(action), local._unresolved_ref_prefix, "")],
      tostring(action)
    )
  ]

  tags = {
    ManagedBy   = "sls.tf"
    Environment = local.provider_with_defaults.stage
  }

  depends_on = [null_resource.config_validation]
}
