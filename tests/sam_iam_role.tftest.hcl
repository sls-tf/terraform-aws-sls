# AWS::IAM::Role + explicit function Role honoring.

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

run "iam_role_created_and_function_role_honored" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-iam-role.yaml"
    config_format = "sam"
  }

  # The AWS::IAM::Role is created with its inline policy.
  assert {
    condition     = length(aws_iam_role.custom) == 1
    error_message = "Expected one custom IAM role."
  }
  assert {
    condition     = aws_iam_role.custom["StreamingRole"].name == "StreamingRole"
    error_message = "Role name should default to the logical ID when no RoleName is set."
  }
  assert {
    condition     = length(aws_iam_role_policy.custom) == 1
    error_message = "Expected one inline role policy (allowStream)."
  }

  # Only PlainFunction gets a module-created execution role; VideoStreamFunction
  # honors its explicit Role and gets none.
  assert {
    condition     = length(aws_iam_role.lambda_execution) == 1
    error_message = "Only the no-Role function should get a per-function role."
  }
  assert {
    condition     = contains(keys(aws_iam_role.lambda_execution), "PlainFunction")
    error_message = "PlainFunction should have a per-function role."
  }
  assert {
    condition     = !contains(keys(aws_iam_role.lambda_execution), "VideoStreamFunction")
    error_message = "VideoStreamFunction must not get a per-function role (it has an explicit Role)."
  }

  # Both functions still exist.
  assert {
    condition     = length(aws_lambda_function.functions) == 2
    error_message = "Expected two functions."
  }

  # No unsupported-resource errors for AWS::IAM::Role.
  assert {
    condition     = length(local.custom_resource_validation_errors) == 0
    error_message = "AWS::IAM::Role must not raise unsupported-type errors."
  }
}
