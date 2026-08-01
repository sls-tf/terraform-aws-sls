# Test: Dynamic alarm sets — one alarm per (group, metric, derived resource)
# resource_names: [] expands to ALL created resources of the class; explicit
# lists and per-group action overrides are honored.

mock_provider "aws" {}

run "alarm_set_expansion" {
  command = plan

  variables {
    config_path = "tests/fixtures/alarm-sets.yml"
  }

  # lambda: 2 metrics x 2 functions = 4; dynamodb: 1 metric x 1 table = 1;
  # api_gateway: 1 metric x 1 explicit name = 1
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.set) == 6
    error_message = "Expected 6 alarms from the set expansion, got ${length(aws_cloudwatch_metric_alarm.set)}"
  }

  # Empty resource_names expanded to every created function (generated names)
  assert {
    condition     = contains(keys(aws_cloudwatch_metric_alarm.set), "lambda-Errors-alarm-sets-dev-ingest")
    error_message = "ingest Errors alarm missing from lambda group expansion"
  }

  assert {
    condition     = contains(keys(aws_cloudwatch_metric_alarm.set), "lambda-Throttles-alarm-sets-dev-process")
    error_message = "process Throttles alarm missing from lambda group expansion"
  }

  # Omitted resource_names also expands to all resources of the class
  assert {
    condition     = contains(keys(aws_cloudwatch_metric_alarm.set), "dynamodb-ThrottledRequests-events-table-dev")
    error_message = "dynamodb group did not expand to the created table"
  }
}

run "alarm_set_properties" {
  command = plan

  variables {
    config_path = "tests/fixtures/alarm-sets.yml"
  }

  # Class defaults: namespace + dimension name
  assert {
    condition     = aws_cloudwatch_metric_alarm.set["lambda-Errors-alarm-sets-dev-ingest"].namespace == "AWS/Lambda"
    error_message = "lambda class namespace default not applied"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.set["lambda-Errors-alarm-sets-dev-ingest"].dimensions["FunctionName"] == "alarm-sets-dev-ingest"
    error_message = "lambda class dimension not applied"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.set["dynamodb-ThrottledRequests-events-table-dev"].dimensions["TableName"] == "events-table-dev"
    error_message = "dynamodb class dimension not applied"
  }

  # Per-metric config
  assert {
    condition     = aws_cloudwatch_metric_alarm.set["lambda-Errors-alarm-sets-dev-ingest"].period == 300 && aws_cloudwatch_metric_alarm.set["lambda-Errors-alarm-sets-dev-ingest"].evaluation_periods == 2
    error_message = "Metric period/evaluation periods not applied"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.set["lambda-Errors-alarm-sets-dev-ingest"].treat_missing_data == "notBreaching"
    error_message = "treatMissingData not applied"
  }

  # Metric-level defaults (period 300 / statistic Sum / evaluationPeriods 1)
  assert {
    condition     = aws_cloudwatch_metric_alarm.set["lambda-Throttles-alarm-sets-dev-ingest"].evaluation_periods == 1 && aws_cloudwatch_metric_alarm.set["lambda-Throttles-alarm-sets-dev-ingest"].statistic == "Sum"
    error_message = "Metric defaults not applied"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.set["api_gateway-5XXError-my-shared-api"].statistic == "Average"
    error_message = "Explicit statistic not applied"
  }
}

run "alarm_set_actions" {
  command = plan

  variables {
    config_path = "tests/fixtures/alarm-sets.yml"
  }

  # defaults.actions (Ref to template topic) applied to groups without overrides
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.set["lambda-Errors-alarm-sets-dev-ingest"].alarm_actions) == 1
    error_message = "Default actions not applied to lambda group"
  }

  # Group-level override with a literal ARN
  assert {
    condition     = tolist(aws_cloudwatch_metric_alarm.set["api_gateway-5XXError-my-shared-api"].alarm_actions) == tolist(["arn:aws:sns:us-east-1:123456789012:apigw-alerts"])
    error_message = "Group-level action override not applied"
  }
}
