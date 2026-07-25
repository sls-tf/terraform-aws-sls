# Test: Function-level async invoke config + DLQ
# SAM DeadLetterQueue / EventInvokeConfig and serverless yaml
# onError / maximumEventAge / maximumRetryAttempts / destinations.

mock_provider "aws" {}

run "sam_function_dlq_wired" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-function-async.yaml"
    config_format = "sam"
  }

  # Only the declaring function gets a dead_letter_config
  assert {
    condition     = length(aws_lambda_function.functions["HeldoffCheck"].dead_letter_config) == 1
    error_message = "HeldoffCheck DeadLetterQueue not mapped to dead_letter_config"
  }

  assert {
    condition     = length(aws_lambda_function.functions["PlainFunction"].dead_letter_config) == 0
    error_message = "PlainFunction should have no dead_letter_config"
  }

  # Module-created role gets DLQ delivery permission
  assert {
    condition     = length(aws_iam_role_policy.lambda_dlq) == 1
    error_message = "Expected 1 DLQ role policy, got ${length(aws_iam_role_policy.lambda_dlq)}"
  }

  # (policy body embeds the co-planned queue ARN, unknown at plan — the DLQ
  # policy's existence and keying is what's assertable here)
  assert {
    condition     = contains(keys(aws_iam_role_policy.lambda_dlq), "HeldoffCheck")
    error_message = "DLQ role policy not keyed to HeldoffCheck"
  }
}

run "sam_event_invoke_config" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-function-async.yaml"
    config_format = "sam"
  }

  assert {
    condition     = length(aws_lambda_function_event_invoke_config.functions) == 1
    error_message = "Expected 1 event invoke config, got ${length(aws_lambda_function_event_invoke_config.functions)}"
  }

  assert {
    condition     = aws_lambda_function_event_invoke_config.functions["HeldoffCheck"].maximum_event_age_in_seconds == 3600
    error_message = "MaximumEventAgeInSeconds not translated"
  }

  assert {
    condition     = aws_lambda_function_event_invoke_config.functions["HeldoffCheck"].maximum_retry_attempts == 1
    error_message = "MaximumRetryAttempts not translated"
  }

  assert {
    condition     = length(aws_lambda_function_event_invoke_config.functions["HeldoffCheck"].destination_config[0].on_failure) == 1
    error_message = "OnFailure destination not wired"
  }
}

run "yaml_function_async" {
  command = plan

  variables {
    config_path = "tests/fixtures/function-async.yml"
  }

  # onError (Ref to a template SNS topic) -> dead_letter_config
  assert {
    condition     = length(aws_lambda_function.functions["worker"].dead_letter_config) == 1
    error_message = "yaml onError not mapped to dead_letter_config"
  }

  assert {
    condition     = length(aws_lambda_function.functions["plain"].dead_letter_config) == 0
    error_message = "plain function should have no dead_letter_config"
  }

  assert {
    condition     = aws_lambda_function_event_invoke_config.functions["worker"].maximum_event_age_in_seconds == 7200
    error_message = "yaml maximumEventAge not translated"
  }

  # Explicit 0 retries must survive (not be coalesced away)
  assert {
    condition     = aws_lambda_function_event_invoke_config.functions["worker"].maximum_retry_attempts == 0
    error_message = "yaml maximumRetryAttempts: 0 not preserved"
  }

  # Literal external destination ARN passes through
  assert {
    condition     = aws_lambda_function_event_invoke_config.functions["worker"].destination_config[0].on_failure[0].destination == "arn:aws:sqs:us-east-1:123456789012:external-failures"
    error_message = "Literal onFailure destination not passed through"
  }

  # DLQ policy on the module-created role (body embeds a co-planned ARN,
  # unknown at plan)
  assert {
    condition     = contains(keys(aws_iam_role_policy.lambda_dlq), "worker")
    error_message = "DLQ role policy not keyed to worker"
  }
}

run "sam_schedule_parity_extensions" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-function-async.yaml"
    config_format = "sam"
  }

  # Explicit rule name instead of the generated "<service>-<stage>-..." form
  assert {
    condition     = aws_cloudwatch_event_rule.schedule["ScheduledFn-schedule-0"].name == "events-scheduled-fn-develop"
    error_message = "Schedule Name not honored"
  }

  assert {
    condition     = aws_cloudwatch_event_rule.schedule["ScheduledFn-schedule-0"].description == "Periodic poll"
    error_message = "Schedule Description not honored"
  }

  # Explicit target id + retry policy
  assert {
    condition     = aws_cloudwatch_event_target.schedule["ScheduledFn-schedule-0"].target_id == "scheduled_fn"
    error_message = "Schedule TargetId not honored"
  }

  assert {
    condition     = aws_cloudwatch_event_target.schedule["ScheduledFn-schedule-0"].retry_policy[0].maximum_retry_attempts == 2 && aws_cloudwatch_event_target.schedule["ScheduledFn-schedule-0"].retry_policy[0].maximum_event_age_in_seconds == 86400
    error_message = "Schedule RetryPolicy not honored"
  }

  # Explicit permission Sid
  assert {
    condition     = aws_lambda_permission.schedule_events["ScheduledFn-schedule-0"].statement_id == "AllowExecutionFromEventBridgeSchedule-develop"
    error_message = "Schedule PermissionSid not honored"
  }
}
