# ============================================================================
# Extension registry (extensions.tf)
# ============================================================================
# Extensions are sls.tf-only config that neither SAM nor Serverless Framework
# defines. These tests pin the two properties the registry exists to provide:
#
#   1. Invisible unless used — a config with no extension keys reports none and
#      creates nothing.
#   2. Presence IS enablement — a config with extension keys reports them at
#      plan time, with no separate flag that could still be off.
#
# Behaviour preservation for the extensions themselves lives in
# alarm_sets.tftest.hcl, cloudwatch_observability.tftest.hcl and
# custom_domain.tftest.hcl — the registry is a refactor of HOW those configs are
# read, not of what they mean.

mock_provider "aws" {}

# --- serverless yaml -------------------------------------------------------

run "yaml_alarms_reported_active" {
  command = plan

  variables {
    config_path                 = "tests/fixtures/alarm-sets.yml"
    extension_legacy_key_notice = false
  }

  assert {
    condition     = contains(keys(output.extensions_active), "Alarms")
    error_message = "alarms: in serverless yaml should report the Alarms extension as active, got: ${join(", ", keys(output.extensions_active))}"
  }

  # The registry declares which parse each extension is read from — this is the
  # fact that was previously tribal knowledge and cost a silent
  # misconfiguration to learn.
  assert {
    condition     = output.extensions_active["Alarms"].parse == "structural"
    error_message = "Alarms should declare the structural parse, got: ${output.extensions_active["Alarms"].parse}"
  }

  assert {
    condition     = output.extensions_active["Alarms"].source == "alarms"
    error_message = "Alarms in yaml format should report the yaml key as its source, got: ${output.extensions_active["Alarms"].source}"
  }

  # Absent extensions must not appear at all — "declared but empty" is the
  # distinction that made version skew silent.
  assert {
    condition     = !contains(keys(output.extensions_active), "Dashboard")
    error_message = "Dashboard is not configured in this fixture and must not report as active"
  }
}

run "yaml_dashboard_reported_active" {
  command = plan

  variables {
    config_path                 = "tests/fixtures/event-service-parity.yml"
    extension_legacy_key_notice = false
  }

  assert {
    condition     = contains(keys(output.extensions_active), "Dashboard")
    error_message = "dashboard: in serverless yaml should report the Dashboard extension as active, got: ${join(", ", keys(output.extensions_active))}"
  }

  # Guards the yaml branch of _extension_dashboard_json specifically: a
  # registry that resolved this to null would still plan cleanly and create no
  # dashboard, which is the failure mode the registry exists to prevent.
  assert {
    condition     = length(aws_cloudwatch_dashboard.generated) == 1
    error_message = "Dashboard reported active but no dashboard resource was created — the registry lookup is not reaching the implementation"
  }
}

run "no_extensions_reports_none" {
  command = plan

  variables {
    config_path = "tests/fixtures/valid-minimal.yml"
  }

  assert {
    condition     = length(output.extensions_active) == 0
    error_message = "A config with no extension keys must report no active extensions, got: ${join(", ", keys(output.extensions_active))}"
  }
}

# --- SAM -------------------------------------------------------------------

run "sam_metadata_extensions_reported_active" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-extensions.yaml"
    config_format = "sam"
  }

  assert {
    condition     = length(local.validation_errors) == 0
    error_message = "Expected no validation errors, got: ${join(", ", local.validation_errors)}"
  }

  assert {
    condition     = contains(keys(output.extensions_active), "Alarms") && contains(keys(output.extensions_active), "Dashboard")
    error_message = "Metadata.SlsTf.Alarms and .Dashboard should both report active, got: ${join(", ", keys(output.extensions_active))}"
  }

  assert {
    condition     = output.extensions_active["Alarms"].source == "Metadata.SlsTf.Alarms"
    error_message = "Alarms in SAM format should report the SAM key as its source, got: ${output.extensions_active["Alarms"].source}"
  }

  # Metadata carries other tools' config (this fixture has Metadata.ServiceName,
  # as do several others). Extension handling is scoped to Metadata.SlsTf.* and
  # must never claim a foreign Metadata key.
  assert {
    condition     = length(output.extensions_active) == 2
    error_message = "Only the two configured extensions should be active — a foreign Metadata key must not register, got: ${join(", ", keys(output.extensions_active))}"
  }

  # CustomDomain is declared in the registry but not configured here.
  assert {
    condition     = !contains(keys(output.extensions_active), "CustomDomain")
    error_message = "CustomDomain is not configured in this fixture and must not report as active"
  }

  # The registry read must reach the implementation, not just the output:
  # 1 metric x 1 function.
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.set) == 1
    error_message = "Expected 1 alarm from the SAM Metadata.SlsTf.Alarms set, got ${length(aws_cloudwatch_metric_alarm.set)}"
  }
}

# --- version ---------------------------------------------------------------

run "module_version_is_reported" {
  command = plan

  variables {
    config_path = "tests/fixtures/valid-minimal.yml"
  }

  # A module cannot read its own source ref, so this is hand-maintained in
  # version.tf and kept honest by `make check-version`. Every extension
  # diagnostic that names a version reads it from here.
  assert {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", output.module_version))
    error_message = "module_version should be a bare semver string, got: ${output.module_version}"
  }
}

# --- serverless-yaml namespace (custom.slsTf) ------------------------------

run "namespaced_yaml_keys_resolve" {
  command = plan

  variables {
    config_path = "tests/fixtures/extensions-namespaced.yml"
  }

  assert {
    condition     = contains(keys(output.extensions_active), "Alarms") && contains(keys(output.extensions_active), "Dashboard")
    error_message = "custom.slsTf.alarms and .dashboard should both report active, got: ${join(", ", keys(output.extensions_active))}"
  }

  assert {
    condition     = output.extensions_active["Alarms"].source == "custom.slsTf.alarms"
    error_message = "Alarms should report the namespaced key as its source, got: ${output.extensions_active["Alarms"].source}"
  }

  # Identical config to alarm-sets.yml, addressed differently: the namespaced
  # spelling must produce the same 6 alarms as the top-level one.
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.set) == 6
    error_message = "Namespaced alarms should expand identically to the top-level spelling, got ${length(aws_cloudwatch_metric_alarm.set)}"
  }

  assert {
    condition     = length(aws_cloudwatch_dashboard.generated) == 1
    error_message = "Namespaced dashboard config should create a dashboard"
  }
}

run "legacy_top_level_keys_still_work" {
  command = plan

  variables {
    config_path                 = "tests/fixtures/alarm-sets.yml"
    extension_legacy_key_notice = false
  }

  # The pre-namespace spelling is supported indefinitely — event-service parity
  # is why alarm sets exist. It emits a check-block notice, not an error.
  assert {
    condition     = length(local.validation_errors) == 0
    error_message = "Legacy top-level alarms: must not be an error, got: ${join(", ", local.validation_errors)}"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.set) == 6
    error_message = "Legacy top-level alarms: should still expand to 6 alarms, got ${length(aws_cloudwatch_metric_alarm.set)}"
  }
}

run "duplicate_spellings_error" {
  command = plan

  variables {
    config_path                 = "tests/fixtures/extensions-duplicate-key.yml"
    extension_legacy_key_notice = false
  }

  # Defining an extension at both spellings must fail rather than silently
  # picking one — silent precedence is the failure mode the registry removes.
  expect_failures = [
    null_resource.config_validation,
  ]
}

# --- unknown keys and misspelled namespace (phase 3) -----------------------

run "unknown_key_under_namespace_errors" {
  command = plan

  variables {
    config_path = "tests/fixtures/extensions-unknown-key.yml"
  }

  expect_failures = [
    null_resource.config_validation,
  ]
}

run "unknown_key_message_names_key_and_suggestion" {
  command = plan

  variables {
    config_path                     = "tests/fixtures/extensions-unknown-key.yml"
    extension_unknown_key_behaviour = "warn"
  }

  # warn mode reports through the check block rather than failing the plan.
  expect_failures = [
    check.extension_unknown_keys,
  ]

  # In warn mode the plan succeeds, so the message itself can be asserted.
  # This is the diagnostic the motivating incident needed and did not get:
  # it must name the offending key, the nearest match, and the running version.
  assert {
    condition     = length(local.extension_unknown_key_errors) == 1
    error_message = "Expected exactly one unknown-key error, got ${length(local.extension_unknown_key_errors)}"
  }

  assert {
    condition     = can(regex("Unknown sls.tf extension 'alarm' under custom.slsTf", local.extension_unknown_key_errors[0]))
    error_message = "Message should name the offending key and namespace, got: ${local.extension_unknown_key_errors[0]}"
  }

  assert {
    condition     = can(regex("Did you mean 'alarms'", local.extension_unknown_key_errors[0]))
    error_message = "Message should suggest the nearest known key, got: ${local.extension_unknown_key_errors[0]}"
  }

  assert {
    condition     = can(regex("supported by sls.tf v${local.module_version}", local.extension_unknown_key_errors[0]))
    error_message = "Message should name the running module version, got: ${local.extension_unknown_key_errors[0]}"
  }

  # The typo'd key must not silently resolve to anything.
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.set) == 0
    error_message = "A typo'd extension key must not create resources"
  }
}

run "warn_mode_does_not_fail_the_plan" {
  command = plan

  variables {
    config_path                     = "tests/fixtures/extensions-unknown-key.yml"
    extension_unknown_key_behaviour = "warn"
  }

  # warn mode reports through the check block rather than failing the plan.
  expect_failures = [
    check.extension_unknown_keys,
  ]

  # The escape hatch for rolling a large estate forward: the problem is
  # reported, but nothing blocks.
  assert {
    condition     = length(local.validation_errors) == 0
    error_message = "warn mode must not put extension problems in validation_errors, got: ${join(", ", local.validation_errors)}"
  }
}

run "misspelled_namespace_errors" {
  command = plan

  variables {
    config_path = "tests/fixtures/extensions-bad-namespace.yml"
  }

  # custom.slstf.* is not "an unknown key under the namespace" — it is no
  # namespace at all, so the unknown-key check alone would never fire.
  expect_failures = [
    null_resource.config_validation,
  ]
}

run "misspelled_namespace_message" {
  command = plan

  variables {
    config_path                     = "tests/fixtures/extensions-bad-namespace.yml"
    extension_unknown_key_behaviour = "warn"
  }

  # warn mode reports through the check block rather than failing the plan.
  expect_failures = [
    check.extension_unknown_keys,
  ]

  assert {
    condition     = length(local.extension_namespace_errors) == 1
    error_message = "Expected one namespace error, got ${length(local.extension_namespace_errors)}"
  }

  assert {
    condition     = can(regex("found 'slstf', expected 'slsTf'", local.extension_namespace_errors[0]))
    error_message = "Message should name both spellings, got: ${local.extension_namespace_errors[0]}"
  }
}

run "foreign_custom_keys_are_not_extensions" {
  command = plan

  variables {
    config_path = "tests/fixtures/extensions-foreign-custom-keys.yml"
  }

  # webpack:, serverless-offline: and myOwnThing: under custom: are other
  # tools' config. Strictness is scoped to custom.slsTf and must not touch them.
  assert {
    condition     = length(local.validation_errors) == 0
    error_message = "Foreign custom: keys must not be rejected, got: ${join(", ", local.validation_errors)}"
  }

  assert {
    condition     = contains(keys(output.extensions_active), "Dashboard")
    error_message = "The real extension alongside foreign keys should still resolve"
  }

  assert {
    condition     = length(output.extensions_active) == 1
    error_message = "Foreign custom: keys must not register as extensions, got: ${join(", ", keys(output.extensions_active))}"
  }
}
