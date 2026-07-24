# Test: Centrally-declared multi-target EventBridge rules (AWS::Events::Rule)
# One rule, multiple independently-configured targets (lambda + per-target DLQ +
# retry policy), plus a non-lambda (external event bus) target.

mock_provider "aws" {}

run "rule_and_targets_created" {
  command = plan

  variables {
    config_path = "tests/fixtures/events-rules-multi-target.yml"
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.cfn) == 1
    error_message = "Expected 1 central rule, got ${length(aws_cloudwatch_event_rule.cfn)}"
  }

  assert {
    condition     = length(aws_cloudwatch_event_target.cfn) == 3
    error_message = "Expected 3 targets on the rule, got ${length(aws_cloudwatch_event_target.cfn)}"
  }

  # Only the two lambda targets get invoke permissions
  assert {
    condition     = length(aws_lambda_permission.cfn_events_rule) == 2
    error_message = "Expected 2 lambda permissions, got ${length(aws_lambda_permission.cfn_events_rule)}"
  }
}

run "rule_properties" {
  command = plan

  variables {
    config_path = "tests/fixtures/events-rules-multi-target.yml"
  }

  assert {
    condition     = aws_cloudwatch_event_rule.cfn["PanelEventsRule"].name == "panel-events-dev"
    error_message = "Rule name not translated"
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.cfn["PanelEventsRule"].event_pattern).source[0] == "custom.panels"
    error_message = "Object EventPattern not JSON-encoded"
  }

  assert {
    condition     = aws_cloudwatch_event_rule.cfn["PanelEventsRule"].event_bus_name == "default"
    error_message = "Rule event bus not translated"
  }
}

run "target_configuration" {
  command = plan

  variables {
    config_path = "tests/fixtures/events-rules-multi-target.yml"
  }

  # Per-target retry policies are independent
  assert {
    condition     = aws_cloudwatch_event_target.cfn["PanelEventsRule-0"].retry_policy[0].maximum_retry_attempts == 4
    error_message = "Enricher target retry policy not translated"
  }

  assert {
    condition     = aws_cloudwatch_event_target.cfn["PanelEventsRule-1"].retry_policy[0].maximum_retry_attempts == 2
    error_message = "Auditor target retry policy not translated"
  }

  assert {
    condition     = aws_cloudwatch_event_target.cfn["PanelEventsRule-0"].retry_policy[0].maximum_event_age_in_seconds == 3600
    error_message = "Enricher target max event age not translated"
  }

  # Per-target DLQs exist (ARNs resolve to co-planned queues, unknown at plan)
  assert {
    condition     = length(aws_cloudwatch_event_target.cfn["PanelEventsRule-0"].dead_letter_config) == 1
    error_message = "Enricher target DLQ not wired"
  }

  assert {
    condition     = length(aws_cloudwatch_event_target.cfn["PanelEventsRule-1"].dead_letter_config) == 1
    error_message = "Auditor target DLQ not wired"
  }

  # Non-lambda target: literal external bus ARN passes through, no DLQ
  assert {
    condition     = aws_cloudwatch_event_target.cfn["PanelEventsRule-2"].arn == "arn:aws:events:us-east-1:123456789012:event-bus/central"
    error_message = "External bus target ARN not passed through"
  }

  assert {
    condition     = length(aws_cloudwatch_event_target.cfn["PanelEventsRule-2"].dead_letter_config) == 0
    error_message = "External bus target should have no DLQ"
  }

  assert {
    condition     = aws_cloudwatch_event_target.cfn["PanelEventsRule-0"].target_id == "enricher"
    error_message = "Target Id not translated"
  }
}

run "target_permissions" {
  command = plan

  variables {
    config_path = "tests/fixtures/events-rules-multi-target.yml"
  }

  assert {
    condition     = aws_lambda_permission.cfn_events_rule["PanelEventsRule-0"].principal == "events.amazonaws.com"
    error_message = "Lambda permission principal incorrect"
  }
}
