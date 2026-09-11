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

# Regression: the lambda alarm class used to take its resource names from the
# RESOLVED function object (local.functions_with_defaults[fn].name). Those names
# are the alarm for_each KEYS, and the resolved object goes unknown the moment
# any sam_template_parameter is a co-planned resource attribute — an ARN for a
# secret created in the same apply, say — so the whole plan aborted with
# "Invalid for_each argument: local.alarm_set_alarms will be known only after
# apply". Reading the name from the structural parse keeps the keys plan-known.
#
# `Environment` is listed as structural so the !Sub in FunctionName resolves to
# the caller's value rather than the template Default — the documented contract
# for any parameter that appears in a resource name.
run "sam_alarm_names_come_from_the_structural_parse" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-alarm-sets-named.yaml"
    config_format = "sam"
    sam_template_parameters = {
      AlertsTopicArn     = "arn:aws:sns:eu-west-2:534294601285:alerts"
      Environment        = "develop"
      CoPlannedSecretArn = "arn:aws:secretsmanager:eu-west-2:534294601285:secret:co-planned-AbCdEf"
    }
    structural_sam_parameters = ["AlertsTopicArn", "Environment"]
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.set) == 1
    error_message = "Expected 1 lambda alarm, got ${length(aws_cloudwatch_metric_alarm.set)}: ${jsonencode(keys(aws_cloudwatch_metric_alarm.set))}"
  }

  # The key is the template's explicit FunctionName, !Sub-resolved against the
  # caller's Environment — not the generated "<prefix>-IngestFunction" fallback.
  assert {
    condition     = contains(keys(aws_cloudwatch_metric_alarm.set), "lambda-Errors-ingest-develop")
    error_message = "Alarm key did not use the template's explicit FunctionName: ${jsonencode(keys(aws_cloudwatch_metric_alarm.set))}"
  }

  # The alarm must point at the same name the lambda resource actually gets.
  assert {
    condition     = aws_cloudwatch_metric_alarm.set["lambda-Errors-ingest-develop"].dimensions["FunctionName"] == aws_lambda_function.functions["IngestFunction"].function_name
    error_message = "Alarm dimension does not match the created function's name"
  }
}

# The guard with teeth. Identical to the run above except `Environment` is NOT
# declared structural, so the structural parse resolves the !Sub against the
# template Default ("dev") while the resolved parse would give the caller's
# value ("develop"). Asserting the Default-derived name is what proves the alarm
# name is read from the structural parse — the property the plan-time-known
# for_each keys depend on. It also pins the footgun this implies, and which
# structural_sam_parameters exists to close: a parameter that appears in a
# resource NAME must be declared structural or the alarm tracks the wrong name.
run "sam_alarm_names_ignore_undeclared_parameters" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-alarm-sets-named.yaml"
    config_format = "sam"
    sam_template_parameters = {
      AlertsTopicArn     = "arn:aws:sns:eu-west-2:534294601285:alerts"
      Environment        = "develop"
      CoPlannedSecretArn = "arn:aws:secretsmanager:eu-west-2:534294601285:secret:co-planned-AbCdEf"
    }
    structural_sam_parameters = ["AlertsTopicArn"]
  }

  assert {
    condition     = contains(keys(aws_cloudwatch_metric_alarm.set), "lambda-Errors-ingest-dev")
    error_message = "Alarm name was not taken from the structural parse: ${jsonencode(keys(aws_cloudwatch_metric_alarm.set))}"
  }
}
