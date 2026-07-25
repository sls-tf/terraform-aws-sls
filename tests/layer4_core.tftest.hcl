# Test: Layer-4 batch 1 — DynamoDB PITR/TTL, S3 lifecycle, custom EventBus,
# X-Ray tracing, layers + KMS.

mock_provider "aws" {}

run "dynamodb_pitr_and_ttl" {
  command = plan

  variables {
    config_path = "tests/fixtures/layer4-core.yml"
  }

  assert {
    condition     = aws_dynamodb_table.custom["HoldoffStore"].point_in_time_recovery[0].enabled == true
    error_message = "PointInTimeRecoverySpecification not mapped"
  }

  assert {
    condition     = aws_dynamodb_table.custom["HoldoffStore"].ttl[0].attribute_name == "expiresAt" && aws_dynamodb_table.custom["HoldoffStore"].ttl[0].enabled == true
    error_message = "TimeToLiveSpecification not mapped"
  }
}

run "s3_lifecycle_rules" {
  command = plan

  variables {
    config_path = "tests/fixtures/layer4-core.yml"
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.custom) == 1
    error_message = "Lifecycle configuration not created"
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.custom["CuratedBucket"].rule[0].expiration[0].days == 1095
    error_message = "ExpirationInDays not mapped"
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.custom["CuratedBucket"].rule[0].filter[0].prefix == "powerbi/raw_events_flattened/"
    error_message = "Lifecycle prefix not mapped"
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.custom["CuratedBucket"].rule[0].status == "Enabled"
    error_message = "Lifecycle status not mapped"
  }
}

run "custom_event_bus" {
  command = plan

  variables {
    config_path = "tests/fixtures/layer4-core.yml"
  }

  assert {
    condition     = aws_cloudwatch_event_bus.cfn["EventsBus"].name == "dev-events-events-bus"
    error_message = "Custom event bus not created"
  }

  # Rule binds to the created bus (unknown value at plan; the binding is what
  # matters — a literal fallthrough would be the known string "default")
  assert {
    condition     = length(aws_cloudwatch_event_rule.cfn) == 1 && length(aws_cloudwatch_event_target.cfn) == 1
    error_message = "Rule/target on the custom bus not created"
  }
}

run "tracing_and_layers" {
  command = plan

  variables {
    config_path = "tests/fixtures/layer4-core.yml"
  }

  # provider.tracing.lambda: true -> Active on worker
  assert {
    condition     = aws_lambda_function.functions["worker"].tracing_config[0].mode == "Active"
    error_message = "provider tracing default not applied"
  }

  # function-level tracing: false opts out
  assert {
    condition     = length(aws_lambda_function.functions["untraced"].tracing_config) == 0
    error_message = "tracing: false should opt the function out"
  }

  # X-Ray policy only on traced functions' roles
  assert {
    condition     = length(aws_iam_role_policy_attachment.lambda_xray) == 1 && contains(keys(aws_iam_role_policy_attachment.lambda_xray), "worker")
    error_message = "X-Ray policy attachment incorrect"
  }

  assert {
    condition     = tolist(aws_lambda_function.functions["worker"].layers) == tolist(["arn:aws:lambda:us-east-1:123456789012:layer:shared:4"])
    error_message = "Layers not mapped"
  }

  assert {
    condition     = aws_lambda_function.functions["worker"].kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/abc-123"
    error_message = "kmsKeyArn not mapped"
  }
}
