# Test: Layer-4 parity against the event-service infrastructure.yaml shape —
# stage-first naming, untagged roles, auto-created DLQs (function + rule
# target), db_access grants, consumer-shaped alarm groups (scalar metrics,
# group-level snake_case settings), anomaly-detection alarms, generated
# dashboard, secret-backed subscription endpoint, nested outputs; plus the SAM
# side: named stage, AWS_IAM route auth, zone-by-name domain.

mock_provider "aws" {
  override_data {
    target = data.aws_region.current
    values = {
      region = "eu-west-1"
    }
  }
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }
}

run "stage_first_naming_and_untagged_roles" {
  command = plan

  variables {
    config_path          = "tests/fixtures/event-service-parity.yml"
    generated_name_order = "stage-service"
    role_tags_enabled    = false
  }

  # Elemental convention: {env}-{service}-{key}
  assert {
    condition     = aws_lambda_function.functions["atp_holdoff_disabled"].function_name == "develop-events-atp_holdoff_disabled"
    error_message = "stage-first generated function name incorrect"
  }

  assert {
    condition     = aws_iam_role.lambda_execution["atp_holdoff_disabled"].name == "develop-events-atp_holdoff_disabled-role"
    error_message = "stage-first generated role name incorrect"
  }

  assert {
    condition     = length(aws_iam_role.lambda_execution["atp_holdoff_disabled"].tags) == 0
    error_message = "role_tags_enabled = false should leave roles untagged"
  }
}

run "auto_created_dlqs" {
  command = plan

  variables {
    config_path          = "tests/fixtures/event-service-parity.yml"
    generated_name_order = "stage-service"
  }

  # Function DLQs auto-created from dlq: {enabled, name}
  assert {
    condition     = length(aws_sqs_queue.function_dlq) == 2
    error_message = "Expected 2 auto-created function DLQs, got ${length(aws_sqs_queue.function_dlq)}"
  }

  assert {
    condition     = aws_sqs_queue.function_dlq["atp_holdoff_disabled"].name == "atp_holdoff_disabled-dlq"
    error_message = "Function DLQ name incorrect"
  }

  # dlq wired into the function + async settings preserved
  assert {
    condition     = length(aws_lambda_function.functions["atp_holdoff_disabled"].dead_letter_config) == 1
    error_message = "Auto DLQ not wired into dead_letter_config"
  }

  assert {
    condition     = aws_lambda_function_event_invoke_config.functions["atp_holdoff_disabled"].maximum_retry_attempts == 2
    error_message = "async retries not preserved alongside auto DLQ"
  }

  # Rule-target DLQ auto-created with the elemental "<rule>-<idx>" name
  assert {
    condition     = aws_sqs_queue.events_target_dlq["all_events_ingress-0"].name == "all_events_ingress-0"
    error_message = "Target DLQ auto-name incorrect"
  }

  assert {
    condition     = length(aws_cloudwatch_event_target.cfn["all_events_ingress-0"].dead_letter_config) == 1
    error_message = "Auto target DLQ not wired"
  }

  assert {
    condition     = length(aws_sqs_queue_policy.events_target_dlq) == 1
    error_message = "Target DLQ queue policy missing"
  }
}

run "db_access_grants" {
  command = plan

  variables {
    config_path = "tests/fixtures/event-service-parity.yml"
  }

  # Only the declaring function gets the policy
  assert {
    condition     = length(aws_iam_role_policy.lambda_db_access) == 1 && contains(keys(aws_iam_role_policy.lambda_db_access), "atp_record_count_metric")
    error_message = "db_access policy keying incorrect"
  }

  assert {
    condition     = aws_iam_role_policy.lambda_db_access["atp_record_count_metric"].name == "db-access-read"
    error_message = "db_access level not reflected in policy name"
  }
}

run "consumer_shaped_alarm_groups" {
  command = plan

  variables {
    config_path = "tests/fixtures/event-service-parity.yml"
  }

  # lambda: 2 scalar metrics x 4 functions = 8; anomaly group: 1 x 1 = 1
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.set) == 9
    error_message = "Expected 9 set alarms, got ${length(aws_cloudwatch_metric_alarm.set)}"
  }

  # Group-level snake_case settings applied to scalar metrics
  assert {
    condition     = aws_cloudwatch_metric_alarm.set["lambda-Errors-events-develop-atp_holdoff_disabled"].period == 60
    error_message = "Group-level period not applied to scalar metric"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.set["lambda-Errors-events-develop-atp_holdoff_disabled"].comparison_operator == "GreaterThanOrEqualToThreshold"
    error_message = "Group-level comparison_operator (snake_case) not applied"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.set["lambda-Errors-events-develop-atp_holdoff_disabled"].dimensions["FunctionName"] == "events-develop-atp_holdoff_disabled"
    error_message = "dimension_key alias not applied"
  }

  # Anomaly-detection alarm: band expression + threshold_metric_id, no static
  # threshold
  assert {
    condition     = aws_cloudwatch_metric_alarm.set["metric_anomaly-ATPEventRecordCount-events"].threshold_metric_id == "ad1"
    error_message = "Anomaly alarm threshold_metric_id missing"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.set["metric_anomaly-ATPEventRecordCount-events"].metric_query) == 2
    error_message = "Anomaly alarm should carry metric + band queries"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.set["metric_anomaly-ATPEventRecordCount-events"].comparison_operator == "LessThanLowerOrGreaterThanUpperThreshold"
    error_message = "Anomaly alarm comparison operator incorrect"
  }
}

run "generated_dashboard" {
  command = plan

  variables {
    config_path = "tests/fixtures/event-service-parity.yml"
  }

  assert {
    condition     = aws_cloudwatch_dashboard.generated["dashboard"].dashboard_name == "event_monitoring"
    error_message = "Generated dashboard name incorrect"
  }

  # lambda widget: 3 default metrics x 4 functions = 12 rows; dynamodb widget:
  # 3 x 1 table = 3 rows
  assert {
    condition     = length(jsondecode(aws_cloudwatch_dashboard.generated["dashboard"].dashboard_body).widgets) == 2
    error_message = "Expected 2 widgets (lambda + dynamodb)"
  }

  assert {
    condition     = length(jsondecode(aws_cloudwatch_dashboard.generated["dashboard"].dashboard_body).widgets[0].properties.metrics) == 12
    error_message = "Lambda widget should chart 3 metrics x 4 functions"
  }
}

run "secret_backed_subscription" {
  command = plan

  variables {
    config_path = "tests/fixtures/event-service-parity.yml"
  }

  assert {
    condition     = length(data.aws_secretsmanager_secret_version.subscription_endpoint) == 1
    error_message = "Secret-backed endpoint lookup not created"
  }

  assert {
    condition     = aws_sns_topic_subscription.custom["PagerDutySubscription"].protocol == "https"
    error_message = "PagerDuty subscription not created"
  }
}

run "nested_outputs" {
  command = plan

  variables {
    config_path = "tests/fixtures/event-service-parity.yml"
  }

  assert {
    condition     = output.lambda_functions["all_events"].function_name == "events-develop-all_events"
    error_message = "Nested lambda_functions output shape incorrect"
  }

  assert {
    condition     = output.dynamodb_tables["AtpHoldoffStore"].table_name == "develop-events-atp-holdoff-store"
    error_message = "Nested dynamodb_tables output shape incorrect"
  }
}

run "sam_stage_auth_and_zone_lookup" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-httpapi-parity.yaml"
    config_format = "sam"
  }

  # Named stage instead of $default
  assert {
    condition     = aws_apigatewayv2_stage.self["HttpApi"].name == "v1"
    error_message = "StageName not honored"
  }

  # AWS_IAM route auth with no authorizer resource
  assert {
    condition     = aws_apigatewayv2_route.self["ReceiveEvents-ANY-proxy+"].authorization_type == "AWS_IAM"
    error_message = "AWS_IAM route auth not applied"
  }

  assert {
    condition     = aws_apigatewayv2_route.self["ReceiveEvents-POST-arc-response-status"].authorization_type == "NONE"
    error_message = "Unauthorized route should stay NONE"
  }

  assert {
    condition     = length(aws_apigatewayv2_authorizer.self) == 0
    error_message = "AWS_IAM must not create a Lambda authorizer"
  }

  # Zone looked up by name; cert self-provisioned against it
  assert {
    condition     = data.aws_route53_zone.self_domain["HttpApi"].name == "texecom-develop.com"
    error_message = "Zone-by-name lookup not created"
  }

  assert {
    condition     = length(aws_acm_certificate.self) == 1 && length(aws_route53_record.self_httpapi) == 1
    error_message = "Cert + alias should provision off the looked-up zone"
  }
}
