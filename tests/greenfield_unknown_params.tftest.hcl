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

  # function_name is ForceNew. Read from the resolved config object it goes
  # unknown as soon as any sam_template_parameter is co-planned, and Terraform
  # then plans a DESTROY AND RECREATE of every function — taking each one's ARN,
  # permissions and event wiring with it. The name depends only on the template
  # and on plan-known parameters, so it must stay known.
  # The function_names OUTPUT must be known too: consumers feed it to
  # aws_lambda_permission.function_name, which is also ForceNew.
  assert {
    condition     = output.function_names_out["HelloFunction"] == "hello-dev"
    error_message = "function_names output must be plan-time known; consumers pass it to ForceNew arguments"
  }

  assert {
    condition     = output.function_name_planned == "hello-dev"
    error_message = "function_name must be plan-time known (got an unknown or wrong value); an unknown here force-replaces every function"
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
