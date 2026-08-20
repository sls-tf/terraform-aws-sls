# Regression test: Metadata.SlsTf.Alarms on a SAM template used to fail plan
# with "Inconsistent conditional result types" for ANY non-trivial Alarms
# shape (i.e. basically always) — alarm_sets_config's sam branch was a plain
# `? :` conditional whose two arms (an object with `defaults` vs `{}`) don't
# statically unify. See alarm-sets.tf's alarm_sets_config local.

mock_provider "aws" {}

override_data {
  target = data.aws_region.current
  values = {
    region = "eu-west-2"
    name   = "eu-west-2"
  }
}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "534294601285"
  }
}

run "sam_alarms_with_defaults_and_custom_group" {
  command = plan

  variables {
    config_path               = "tests/fixtures/sam-alarm-sets.yaml"
    config_format             = "sam"
    sam_template_parameters   = { AlertsTopicArn = "arn:aws:sns:eu-west-2:534294601285:alerts" }
    structural_sam_parameters = ["AlertsTopicArn"]
  }

  # lambda: 1 metric x 1 function (resource_names: [] enumerates IngestFunction)
  # custom_metric: 1 metric x 1 explicit resource_name = 1
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.set) == 2
    error_message = "Expected 2 alarms from the SAM Alarms metadata, got ${length(aws_cloudwatch_metric_alarm.set)}: ${jsonencode(keys(aws_cloudwatch_metric_alarm.set))}"
  }
  # defaults.actions (a template !Ref) applies to a group with no override.
  assert {
    condition     = contains(tolist(aws_cloudwatch_metric_alarm.set["lambda-Errors-sam-service-dev-IngestFunction"].alarm_actions), "arn:aws:sns:eu-west-2:534294601285:alerts")
    error_message = "lambda group did not inherit defaults.actions from the SAM Metadata"
  }

  # A group with its own namespace/dimension/resource_names (not one of the
  # auto-enumerated resource classes) still expands correctly.
  assert {
    condition     = aws_cloudwatch_metric_alarm.set["custom_metric-PartedThing-sample-service"].namespace == "Texecom/Sample"
    error_message = "custom_metric group namespace override not applied"
  }
}
