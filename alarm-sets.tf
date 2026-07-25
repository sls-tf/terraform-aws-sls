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
      try(local.functions_with_defaults[fn].name, null) != null ? tostring(local.functions_with_defaults[fn].name) : "${local._generated_name_prefix}-${fn}"
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

  # (group, metric, resource) -> alarm spec. Metrics may be OBJECTS or plain
  # NAME STRINGS ("Errors"); per-metric settings fall back to group-level
  # settings then hard defaults. Both camelCase and snake_case keys are
  # accepted (comparisonOperator / comparison_operator, dimension /
  # dimension_key, ...), matching real-world monitoring configs.
  alarm_set_alarms = {
    for spec in flatten([
      for group_name, group in try(local.alarm_sets_config.groups, {}) : [
        for metric in [
          for m in try(group.metrics, []) :
          # JSON-laundered: the string and object branches otherwise clash.
          jsondecode(can(tostring(m)) ? jsonencode({ name = tostring(m) }) : jsonencode(m))
          ] : [
          for resource_name in(
            length(try(group.resource_names, [])) > 0
            ? [for r in group.resource_names : tostring(r)]
            : try(local._alarm_class_all_names[group_name], [])
            ) : {
            key           = "${group_name}-${metric.name}-${resource_name}"
            metric_name   = metric.name
            namespace     = tostring(try(group.namespace, try(local._alarm_class_defaults[group_name].namespace, "")))
            dimension     = tostring(try(group.dimension, group.dimension_key, try(local._alarm_class_defaults[group_name].dimension, "")))
            resource_name = resource_name

            period              = try(metric.period, group.period, 300)
            statistic           = try(metric.statistic, group.statistic, "Sum")
            threshold           = try(metric.threshold, group.threshold, null)
            comparison_operator = try(metric.comparisonOperator, metric.comparison_operator, group.comparisonOperator, group.comparison_operator, "GreaterThanOrEqualToThreshold")
            evaluation_periods  = try(metric.evaluationPeriods, metric.evaluation_periods, group.evaluationPeriods, group.evaluation_periods, 1)
            datapoints_to_alarm = try(metric.datapointsToAlarm, metric.datapoints_to_alarm, group.datapointsToAlarm, group.datapoints_to_alarm, null)
            treat_missing_data  = try(metric.treatMissingData, metric.treat_missing_data, group.treatMissingData, group.treat_missing_data, "missing")
            description         = try(metric.description, "Managed by sls.tf alarm set")

            # Anomaly-detection alarms: band instead of static threshold.
            anomaly_detection = try(metric.anomalyDetection, metric.anomaly_detection, group.anomalyDetection, group.anomaly_detection, false)
            anomaly_band      = try(metric.anomalyBandWidth, metric.anomaly_band_width, group.anomalyBandWidth, group.anomaly_band_width, 2)

            actions = try(group.actions, try(local.alarm_sets_config.defaults.actions, []))
          }
        ]
      ]
    ]) : spec.key => spec
  }
}

resource "aws_cloudwatch_metric_alarm" "set" {
  for_each = local.alarm_set_alarms

  alarm_name        = each.key
  alarm_description = each.value.description

  # Static-threshold form: plain namespace/metric/statistic. Anomaly form uses
  # metric_query blocks instead (the two are mutually exclusive on the
  # provider).
  namespace   = each.value.anomaly_detection ? null : each.value.namespace
  metric_name = each.value.anomaly_detection ? null : each.value.metric_name
  dimensions  = each.value.anomaly_detection ? null : { (each.value.dimension) = each.value.resource_name }
  period      = each.value.anomaly_detection ? null : each.value.period
  statistic   = each.value.anomaly_detection ? null : each.value.statistic
  threshold   = each.value.anomaly_detection ? null : each.value.threshold

  comparison_operator = each.value.anomaly_detection ? "LessThanLowerOrGreaterThanUpperThreshold" : each.value.comparison_operator
  evaluation_periods  = each.value.evaluation_periods
  datapoints_to_alarm = each.value.datapoints_to_alarm
  treat_missing_data  = each.value.treat_missing_data

  # Anomaly-detection band: the raw metric plus an ANOMALY_DETECTION_BAND
  # expression it is compared against.
  threshold_metric_id = each.value.anomaly_detection ? "ad1" : null

  dynamic "metric_query" {
    for_each = each.value.anomaly_detection ? ["m1"] : []
    content {
      id          = "m1"
      return_data = true
      metric {
        namespace   = each.value.namespace
        metric_name = each.value.metric_name
        dimensions  = { (each.value.dimension) = each.value.resource_name }
        period      = each.value.period
        stat        = each.value.statistic
      }
    }
  }

  dynamic "metric_query" {
    for_each = each.value.anomaly_detection ? ["ad1"] : []
    content {
      id          = "ad1"
      expression  = "ANOMALY_DETECTION_BAND(m1, ${each.value.anomaly_band})"
      label       = "${each.value.metric_name} (expected band)"
      return_data = true
    }
  }

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
