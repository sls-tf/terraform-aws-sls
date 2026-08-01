# ============================================================================
# Auto-generated monitoring dashboard
# ============================================================================
# Builds a CloudWatch dashboard from the created resource set instead of a
# hand-written DashboardBody:
#
#   yaml (top level):                SAM (template Metadata):
#     dashboard:                       Metadata:
#       name: event_monitoring           SlsTf:
#       services: [lambda, dynamodb,       Dashboard: {name, services}
#                  sqs, eventbridge]
#
# One full-width timeSeries widget per service class; each widget's metric
# rows enumerate that class's resources. Names come from the alarm-set class
# enumeration; an `alarms.groups.<class>.resource_names` list (when non-empty)
# overrides it, so classes without auto-enumeration (api_gateway) reuse the
# names already declared for alarms.

locals {
  # Resolved through the extension registry — see extensions.tf.
  dashboard_config = jsondecode(local.extension_config_json.Dashboard)

  # Default metrics charted per class.
  _dashboard_class_metrics = {
    lambda      = ["Invocations", "Errors", "Duration"]
    dynamodb    = ["ConsumedReadCapacityUnits", "ConsumedWriteCapacityUnits", "ThrottledRequests"]
    sqs         = ["ApproximateNumberOfMessagesVisible", "ApproximateAgeOfOldestMessage"]
    sns         = ["NumberOfMessagesPublished", "NumberOfNotificationsFailed"]
    s3          = ["AllRequests", "4xxErrors", "5xxErrors"]
    eventbridge = ["Invocations", "FailedInvocations"]
    athena      = ["QuerySuccessful", "QueryFailed"]
    api_gateway = ["Count", "4XXError", "5XXError"]
  }

  _dashboard_services = local.dashboard_config != null ? [
    for svc in try(local.dashboard_config.services, keys(local._dashboard_class_metrics)) : tostring(svc)
  ] : []

  # Resource names per charted class: alarm-group override first, else the
  # class enumeration.
  _dashboard_class_names = {
    for svc in local._dashboard_services :
    svc => (
      length(try(local.alarm_sets_config.groups[svc].resource_names, [])) > 0
      ? [for r in local.alarm_sets_config.groups[svc].resource_names : tostring(r)]
      : try(local._alarm_class_all_names[svc], [])
    )
  }

  _dashboard_widgets = [
    for idx, svc in local._dashboard_services : {
      type   = "metric"
      x      = 0
      y      = idx * 6
      width  = 24
      height = 6
      properties = {
        title  = svc
        view   = "timeSeries"
        region = data.aws_region.current.region
        period = 300
        stat   = svc == "lambda" ? "Sum" : "Average"
        metrics = [
          for pair in setproduct(
            local._dashboard_class_metrics[svc],
            local._dashboard_class_names[svc]
            ) : [
            local._alarm_class_defaults[svc].namespace,
            pair[0],
            local._alarm_class_defaults[svc].dimension,
            pair[1],
          ]
        ]
      }
    }
    if length(local._dashboard_class_names[svc]) > 0
  ]
}

resource "aws_cloudwatch_dashboard" "generated" {
  for_each = local.dashboard_config != null ? { dashboard = local.dashboard_config } : {}

  dashboard_name = tostring(try(each.value.name, "${local._generated_name_prefix}-monitoring"))
  dashboard_body = jsonencode({ widgets = local._dashboard_widgets })

  depends_on = [null_resource.config_validation]
}
