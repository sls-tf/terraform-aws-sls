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
    config_path = "tests/fixtures/alarm-sets.yml"
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
    config_path = "tests/fixtures/event-service-parity.yml"
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
