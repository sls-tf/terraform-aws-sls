# Test: CloudWatch dashboard/alarm + SNS subscription translation
# Validates AWS::CloudWatch::Dashboard, AWS::CloudWatch::Alarm and
# AWS::SNS::Subscription translation, including SNS-as-alarm-action wiring.

mock_provider "aws" {}

run "observability_resources_created" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudwatch-observability.yml"
  }

  assert {
    condition     = length(aws_cloudwatch_dashboard.custom) == 1
    error_message = "Expected 1 dashboard, got ${length(aws_cloudwatch_dashboard.custom)}"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.custom) == 1
    error_message = "Expected 1 alarm, got ${length(aws_cloudwatch_metric_alarm.custom)}"
  }

  assert {
    condition     = length(aws_sns_topic_subscription.custom) == 2
    error_message = "Expected 2 SNS subscriptions, got ${length(aws_sns_topic_subscription.custom)}"
  }
}

run "dashboard_properties" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudwatch-observability.yml"
  }

  assert {
    condition     = aws_cloudwatch_dashboard.custom["ServiceDashboard"].dashboard_name == "event-service-dev"
    error_message = "Dashboard name not translated"
  }

  # Object-form DashboardBody is JSON-encoded
  assert {
    condition     = can(jsondecode(aws_cloudwatch_dashboard.custom["ServiceDashboard"].dashboard_body).widgets)
    error_message = "Object DashboardBody not JSON-encoded"
  }
}

run "alarm_properties" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudwatch-observability.yml"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.custom["WorkerErrorsAlarm"].alarm_name == "worker-errors-dev"
    error_message = "Alarm name not translated"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.custom["WorkerErrorsAlarm"].comparison_operator == "GreaterThanOrEqualToThreshold"
    error_message = "Alarm comparison operator not translated"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.custom["WorkerErrorsAlarm"].namespace == "AWS/Lambda" && aws_cloudwatch_metric_alarm.custom["WorkerErrorsAlarm"].metric_name == "Errors"
    error_message = "Alarm namespace/metric not translated"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.custom["WorkerErrorsAlarm"].period == 300 && aws_cloudwatch_metric_alarm.custom["WorkerErrorsAlarm"].statistic == "Sum"
    error_message = "Alarm period/statistic not translated"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.custom["WorkerErrorsAlarm"].evaluation_periods == 2 && aws_cloudwatch_metric_alarm.custom["WorkerErrorsAlarm"].datapoints_to_alarm == 2
    error_message = "Alarm evaluation periods not translated"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.custom["WorkerErrorsAlarm"].threshold == 5
    error_message = "Alarm threshold not translated"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.custom["WorkerErrorsAlarm"].treat_missing_data == "notBreaching"
    error_message = "Alarm treat_missing_data not translated"
  }

  # Dimension Value {Ref: worker} resolves to the created function's name
  assert {
    condition     = contains(keys(aws_cloudwatch_metric_alarm.custom["WorkerErrorsAlarm"].dimensions), "FunctionName")
    error_message = "Alarm dimensions not translated"
  }
}

run "alarm_sns_actions_wired" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudwatch-observability.yml"
  }

  # One alarm action, resolved from Ref: AlertsTopic (unknown ARN at plan, but
  # the list length is known)
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.custom["WorkerErrorsAlarm"].alarm_actions) == 1
    error_message = "Alarm action from Ref not wired"
  }

  # Literal external ARN passes through
  assert {
    condition     = tolist(aws_cloudwatch_metric_alarm.custom["WorkerErrorsAlarm"].ok_actions) == tolist(["arn:aws:sns:us-east-1:123456789012:external-alerts"])
    error_message = "Literal OK action ARN not passed through"
  }
}

run "sns_subscription_properties" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudwatch-observability.yml"
  }

  # PagerDuty-style https subscription on a template topic
  assert {
    condition     = aws_sns_topic_subscription.custom["PagerDutySubscription"].protocol == "https"
    error_message = "PagerDuty subscription protocol not translated"
  }

  assert {
    condition     = aws_sns_topic_subscription.custom["PagerDutySubscription"].endpoint == "https://events.pagerduty.com/integration/abc123/enqueue"
    error_message = "PagerDuty subscription endpoint not translated"
  }

  # Literal external topic ARN passes through
  assert {
    condition     = aws_sns_topic_subscription.custom["ExternalTopicSubscription"].topic_arn == "arn:aws:sns:us-east-1:123456789012:external-alerts"
    error_message = "External subscription topic ARN not passed through"
  }

  # Object FilterPolicy is JSON-encoded
  assert {
    condition     = jsondecode(aws_sns_topic_subscription.custom["ExternalTopicSubscription"].filter_policy).severity[0] == "critical"
    error_message = "FilterPolicy not JSON-encoded"
  }
}
