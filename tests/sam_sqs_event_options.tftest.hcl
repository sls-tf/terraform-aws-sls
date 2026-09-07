# SAM SQS event source mapping options.
#
# The SAM -> sls translation used to carry only Queue and BatchSize, so a
# template's Enabled, FunctionResponseTypes, MaximumBatchingWindowInSeconds and
# ScalingConfig were dropped on the floor. For a brownfield adoption that is
# not merely a missing feature: an existing mapping with
# FunctionResponseTypes: [ReportBatchItemFailures] silently reverts to
# whole-batch retries, and one pinned Enabled: false comes back enabled.

mock_provider "aws" {}

run "sam_sqs_event_options_are_translated" {
  command = plan

  variables {
    config_path      = "tests/fixtures/sam-sqs-event-options.yaml"
    config_format    = "sam"
    lambda_code_path = "tests/fixtures"
  }

  assert {
    condition = alltrue([
      contains(tolist(aws_lambda_event_source_mapping.event_sources["ProcessorFunction_sqs_0"].function_response_types), "ReportBatchItemFailures"),
      length(aws_lambda_event_source_mapping.event_sources["ProcessorFunction_sqs_0"].function_response_types) == 1,
    ])
    error_message = "FunctionResponseTypes must reach the mapping, got ${jsonencode(aws_lambda_event_source_mapping.event_sources["ProcessorFunction_sqs_0"].function_response_types)}"
  }

  assert {
    condition     = aws_lambda_event_source_mapping.event_sources["ProcessorFunction_sqs_0"].enabled == true
    error_message = "Enabled: true must reach the mapping"
  }

  assert {
    condition     = aws_lambda_event_source_mapping.event_sources["ProcessorFunction_sqs_0"].batch_size == 10
    error_message = "BatchSize must reach the mapping"
  }

  assert {
    condition     = aws_lambda_event_source_mapping.event_sources["ProcessorFunction_sqs_0"].maximum_batching_window_in_seconds == 5
    error_message = "MaximumBatchingWindowInSeconds must reach the mapping"
  }

  assert {
    condition     = one(aws_lambda_event_source_mapping.event_sources["ProcessorFunction_sqs_0"].scaling_config).maximum_concurrency == 20
    error_message = "ScalingConfig.MaximumConcurrency must reach the mapping"
  }

  # Unset options keep the module's existing defaults.
  assert {
    condition     = aws_lambda_event_source_mapping.event_sources["MinimalFunction_sqs_0"].enabled == true
    error_message = "An SQS event with no Enabled should default to enabled"
  }

  assert {
    condition     = length(coalesce(aws_lambda_event_source_mapping.event_sources["MinimalFunction_sqs_0"].function_response_types, [])) == 0
    error_message = "An SQS event with no FunctionResponseTypes must leave the argument unset, got ${jsonencode(aws_lambda_event_source_mapping.event_sources["MinimalFunction_sqs_0"].function_response_types)}"
  }

  assert {
    condition     = length(aws_lambda_event_source_mapping.event_sources["MinimalFunction_sqs_0"].scaling_config) == 0
    error_message = "An SQS event with no ScalingConfig must not emit a scaling_config block"
  }

  # Enabled: false is a value, not an absence.
  assert {
    condition     = aws_lambda_event_source_mapping.event_sources["DisabledMappingFunction_sqs_0"].enabled == false
    error_message = "Enabled: false must be preserved, not defaulted back to true"
  }
}
