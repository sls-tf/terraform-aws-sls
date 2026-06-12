# Greenfield repro: a consumer passes sam_template_parameters values that are
# computed in the SAME plan (e.g. aws_secretsmanager_secret.x.arn on a fresh
# ephemeral account). Every for_each whose keys derive from the parsed config
# must still have plan-time-known keys. Uses a wrapper module because the
# unknown value must be born inside the planned configuration.

mock_provider "aws" {}

run "greenfield_plan_with_unknown_param" {
  command = plan

  providers = {
    aws = aws
  }

  module {
    source = "./tests/fixtures/greenfield-wrapper"
  }

  # Keys must be plan-time known even though the parameter value is unknown.
  assert {
    condition     = tolist(output.function_keys) == tolist(["HelloFunction"])
    error_message = "function for_each keys must be plan-time known"
  }

  assert {
    condition = (
      output.custom_resource_counts.s3_buckets == 1 &&
      output.custom_resource_counts.dynamodb_tables == 1 &&
      output.custom_resource_counts.sns_topics == 1 &&
      output.custom_resource_counts.sqs_queues == 1
    )
    error_message = "custom resource for_each keys must be plan-time known"
  }
}

# Same template, but with the consumer's resource_types allowlist as used by
# identity-service / scheduler-service (functions only). The category maps must
# be statically EMPTY, not unknown.
run "greenfield_plan_functions_only_allowlist" {
  command = plan

  providers = {
    aws = aws
  }

  module {
    source = "./tests/fixtures/greenfield-wrapper"
  }

  variables {
    resource_types = ["AWS::Serverless::Function"]
  }

  assert {
    condition = (
      output.custom_resource_counts.s3_buckets == 0 &&
      output.custom_resource_counts.dynamodb_tables == 0 &&
      output.custom_resource_counts.sns_topics == 0 &&
      output.custom_resource_counts.sqs_queues == 0
    )
    error_message = "allowlisted-out category maps must be statically empty"
  }

  assert {
    condition     = tolist(output.function_keys) == tolist(["HelloFunction"])
    error_message = "functions must still be created under the allowlist"
  }
}
