# Step Functions tests (AWS::Serverless::StateMachine).
#
# The module must create an aws_sfn_state_machine with the definition rendered
# from DefinitionUri + DefinitionSubstitutions, plus an execution role with a
# lambda:InvokeFunction policy derived from LambdaInvokePolicy.

mock_provider "aws" {}

override_data {
  target = data.aws_region.current
  values = {
    region = "eu-west-1"
    name   = "eu-west-1"
  }
}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
  }
}

run "statemachine_creates_sfn_and_role" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-statemachine.yaml"
    config_format = "sam"
  }

  assert {
    condition     = length(aws_sfn_state_machine.this) == 1
    error_message = "Expected one state machine."
  }

  assert {
    condition     = aws_sfn_state_machine.this["EventClipStateMachine"].name == "eventClipStateMachine-dev"
    error_message = "State machine name must resolve from !Sub."
  }

  assert {
    condition     = aws_sfn_state_machine.this["EventClipStateMachine"].type == "STANDARD"
    error_message = "Default state machine type must be STANDARD."
  }

  # Definition substitution must inject the function ARN (no leftover ${...}).
  assert {
    condition     = !can(regex("\\$\\{SaveStreamFunctionArn\\}", aws_sfn_state_machine.this["EventClipStateMachine"].definition))
    error_message = "DefinitionSubstitutions must replace the placeholder."
  }

  assert {
    condition     = can(regex("function:SaveStream-dev", aws_sfn_state_machine.this["EventClipStateMachine"].definition))
    error_message = "Definition must reference the SaveStream function ARN."
  }

  # An execution role and its invoke policy.
  assert {
    condition     = length(aws_iam_role.sfn) == 1
    error_message = "Expected one state machine execution role."
  }

  assert {
    condition     = length(aws_iam_role_policy.sfn) == 1
    error_message = "Expected one state machine invoke policy (from LambdaInvokePolicy)."
  }

  # No unsupported-resource errors for the StateMachine type.
  assert {
    condition     = length(local.custom_resource_validation_errors) == 0
    error_message = "StateMachine must not raise unsupported-type errors."
  }
}
