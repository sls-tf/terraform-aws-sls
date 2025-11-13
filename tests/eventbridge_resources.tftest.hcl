# EventBridge & CloudWatch Event Rule Resource Tests
# Tests for CloudWatch Event Rules, Targets, and Lambda Permissions

# Test: Schedule rule creation with rate expression
run "schedule_rule_rate_expression" {
  command = plan

  variables {
    config_path = "tests/fixtures/schedule-rate-simple.yml"
  }

  # Verify rule created
  assert {
    condition     = length(aws_cloudwatch_event_rule.schedule) == 1
    error_message = "Should create 1 schedule event rule"
  }

  # Verify rule name format
  assert {
    condition     = can(regex("^schedule-test-dev-cronJob-schedule-0$", aws_cloudwatch_event_rule.schedule["cronJob-schedule-0"].name))
    error_message = "Rule name should follow naming convention"
  }

  # Verify schedule expression
  assert {
    condition     = aws_cloudwatch_event_rule.schedule["cronJob-schedule-0"].schedule_expression == "rate(5 minutes)"
    error_message = "Schedule expression should match"
  }

  # Verify enabled state
  assert {
    condition     = aws_cloudwatch_event_rule.schedule["cronJob-schedule-0"].state == "ENABLED"
    error_message = "Rule should be enabled by default"
  }

  # Verify target created
  assert {
    condition     = length(aws_cloudwatch_event_target.schedule) == 1
    error_message = "Should create 1 event target"
  }

  # Verify Lambda permission created
  assert {
    condition     = length(aws_lambda_permission.schedule_events) == 1
    error_message = "Should create 1 Lambda permission"
  }
}

# Test: Schedule rule with cron expression and disabled state
run "schedule_rule_cron_disabled" {
  command = plan

  variables {
    config_path = "tests/fixtures/schedule-cron-object.yml"
  }

  # Verify rule created
  assert {
    condition     = length(aws_cloudwatch_event_rule.schedule) == 1
    error_message = "Should create 1 schedule rule"
  }

  # Verify cron expression
  assert {
    condition     = aws_cloudwatch_event_rule.schedule["dailyReport-schedule-0"].schedule_expression == "cron(0 12 * * ? *)"
    error_message = "Cron expression should match"
  }

  # Verify disabled state
  assert {
    condition     = aws_cloudwatch_event_rule.schedule["dailyReport-schedule-0"].state == "DISABLED"
    error_message = "Rule should be disabled when enabled: false"
  }

  # Verify description
  assert {
    condition     = aws_cloudwatch_event_rule.schedule["dailyReport-schedule-0"].description == "Daily report generation at noon UTC"
    error_message = "Description should match"
  }
}

# Test: EventBridge rule with pattern
run "eventbridge_rule_with_pattern" {
  command = plan

  variables {
    config_path = "tests/fixtures/eventbridge-pattern.yml"
  }

  # Verify rule created
  assert {
    condition     = length(aws_cloudwatch_event_rule.eventbridge) == 1
    error_message = "Should create 1 eventBridge rule"
  }

  # Verify rule name
  assert {
    condition     = can(regex("^eventbridge-test-dev-ec2Handler-eventbridge-0$", aws_cloudwatch_event_rule.eventbridge["ec2Handler-eventbridge-0"].name))
    error_message = "Rule name should follow naming convention"
  }

  # Verify default event bus
  assert {
    condition     = aws_cloudwatch_event_rule.eventbridge["ec2Handler-eventbridge-0"].event_bus_name == "default"
    error_message = "Event bus should default to 'default'"
  }

  # Verify enabled state
  assert {
    condition     = aws_cloudwatch_event_rule.eventbridge["ec2Handler-eventbridge-0"].state == "ENABLED"
    error_message = "Rule should be enabled by default"
  }

  # Verify target created
  assert {
    condition     = length(aws_cloudwatch_event_target.eventbridge) == 1
    error_message = "Should create 1 event target"
  }

  # Verify Lambda permission created
  assert {
    condition     = length(aws_lambda_permission.eventbridge_events) == 1
    error_message = "Should create 1 Lambda permission"
  }
}

# Test: EventBridge with custom event bus
run "eventbridge_custom_bus" {
  command = plan

  variables {
    config_path = "tests/fixtures/eventbridge-custom-bus.yml"
  }

  # Verify custom event bus
  assert {
    condition     = aws_cloudwatch_event_rule.eventbridge["customHandler-eventbridge-0"].event_bus_name == "custom-event-bus"
    error_message = "Event bus should match custom value"
  }

  # Verify target uses custom bus
  assert {
    condition     = aws_cloudwatch_event_target.eventbridge["customHandler-eventbridge-0"].event_bus_name == "custom-event-bus"
    error_message = "Target should use custom event bus"
  }
}

# Test: Multiple events per function
run "multiple_events_resources" {
  command = plan

  variables {
    config_path = "tests/fixtures/schedule-multiple-events.yml"
  }

  # Verify multiple schedule rules
  assert {
    condition     = length(aws_cloudwatch_event_rule.schedule) == 2
    error_message = "Should create 2 schedule rules"
  }

  # Verify eventBridge rule
  assert {
    condition     = length(aws_cloudwatch_event_rule.eventbridge) == 1
    error_message = "Should create 1 eventBridge rule"
  }

  # Verify targets created
  assert {
    condition     = length(aws_cloudwatch_event_target.schedule) == 2
    error_message = "Should create 2 schedule targets"
  }

  assert {
    condition     = length(aws_cloudwatch_event_target.eventbridge) == 1
    error_message = "Should create 1 eventBridge target"
  }

  # Verify Lambda permissions
  assert {
    condition     = length(aws_lambda_permission.schedule_events) == 2
    error_message = "Should create 2 schedule Lambda permissions"
  }

  assert {
    condition     = length(aws_lambda_permission.eventbridge_events) == 1
    error_message = "Should create 1 eventBridge Lambda permission"
  }
}

# Test: Outputs
run "eventbridge_outputs" {
  command = plan

  variables {
    config_path = "tests/fixtures/schedule-multiple-events.yml"
  }

  # Verify schedule outputs
  assert {
    condition     = output.schedule_event_count == 2
    error_message = "Should output count of 2 schedule events"
  }

  # Verify eventbridge outputs
  assert {
    condition     = output.eventbridge_event_count == 1
    error_message = "Should output count of 1 eventBridge event"
  }
}
