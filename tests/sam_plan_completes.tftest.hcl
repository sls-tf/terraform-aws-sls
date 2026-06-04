# SAM Plan Completion Tests
#
# Regression guard for the "Inconsistent conditional result types" failure that
# blocked the entire SAM path at plan time under Terraform's structural type
# unification (locals.tf `parsed_config`). The unused yamldecode(file_content)
# branch inferred a concrete object type from the static SAM template that could
# not unify with the translated sam_as_sls_config object, so every SAM config
# errored before any resource was planned. Branches are now JSON-laundered to the
# dynamic `any` type. This test plans a representative SAM template all the way to
# resources and asserts they materialise.
#
# Uses a mock AWS provider (the SAM preprocessor still runs via data.external), so
# it needs neither LocalStack nor AWS credentials.

mock_provider "aws" {}

run "sam_template_plans_to_resources" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-simple.yaml"
    config_format = "sam"
  }

  assert {
    condition     = length(local.functions_with_defaults) == 1
    error_message = "The SAM HelloFunction should be parsed into exactly one function"
  }

  assert {
    condition     = length(aws_lambda_function.functions) == 1
    error_message = "The SAM function should plan to one aws_lambda_function"
  }

  assert {
    condition     = length(aws_api_gateway_method.endpoints) == 1
    error_message = "The SAM Api event (GET /hello) should plan to one API Gateway method"
  }
}

run "sam_globals_plan_to_resources" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-globals.yaml"
    config_format = "sam"
  }

  assert {
    condition     = length(aws_lambda_function.functions) > 0
    error_message = "A SAM template using Globals should plan to at least one function"
  }
}
