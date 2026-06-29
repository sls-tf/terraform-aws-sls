# Loud-failure contract for SAM preprocessing.
#
# scripts/sam-preprocessor.js returns {content:"", error:...} when it cannot parse
# a template (missing file, malformed YAML, an unresolved intrinsic in strict mode,
# or no `node` on PATH). That empty content was coalesced away (sam_structure) and
# its error swallowed (sam_condition_params via try()), so the module produced a
# ZERO-resource plan silently — the failure only surfacing far downstream (e.g. an
# aws_lambda_permission "Function not found" in a consuming module, hours later).
#
# The fix is a config_validation precondition over local.sam_preprocessor_errors,
# which inspects the PLAN-KNOWN structure + condition-params reads (NOT the resolved
# sam_yaml read, which DEFERS to apply on a greenfield/ephemeral plan and so cannot
# be checked at plan time — see sam-parser.tf).
#
# NOTE on coverage: the precondition's UNIQUE value is the greenfield-defer case
# (sam_yaml deferred, structure read errors) — only reproducible through a wrapper
# module that births an unknown parameter value in-plan, where the failure lands on
# module.sls's nested precondition. terraform test cannot assert a nested-module
# precondition failure (`expect_failures` only accepts checkable objects in the
# module under test), so that exact path is verified manually, not here. The runs
# below cover what IS expressible: the loud-failure contract end to end, that the
# error local does not false-fire on a valid template, and that the null-safety
# fallback never masks a healthy template.

mock_provider "aws" {}

provider "null" {}

variables {
  config_format = "sam"
}

# Structurally malformed template: the preprocessor's YAML load throws. The plan
# must abort at config_validation with the preprocessing error, never a cryptic
# "Invalid for_each" or a silent empty module.
run "malformed_sam_fails_loudly" {
  command = plan

  variables {
    config_path = "tests/fixtures/sam-malformed.yaml"
  }

  expect_failures = [
    resource.null_resource.config_validation,
  ]
}

# Empty template file: the structure read errors ("Cannot read properties of
# undefined (reading 'Parameters')"). Must also abort loudly.
run "empty_sam_file_fails_loudly" {
  command = plan

  variables {
    config_path = "tests/fixtures/sam-empty-file.yaml"
  }

  expect_failures = [
    resource.null_resource.config_validation,
  ]
}

# A VALID template must NOT trip the new guard: local.sam_preprocessor_errors must
# be empty so config_validation does not false-fire. Directly exercises the new
# error-collection local (sam-parser.tf:sam_preprocessor_errors).
run "valid_sam_has_no_preprocessor_errors" {
  command = plan

  variables {
    config_path = "tests/fixtures/sam-greenfield-unknown.yaml"
  }

  assert {
    condition     = length(local.sam_preprocessor_errors) == 0
    error_message = "A valid SAM template must not report preprocessor errors"
  }
}

# And it must still parse to its functions — guards against the empty-document
# null-safety fallback (sam_structure) masking a healthy template via type coercion.
run "valid_sam_still_parses_functions" {
  command = plan

  variables {
    config_path = "tests/fixtures/sam-greenfield-unknown.yaml"
  }

  assert {
    condition     = length(keys(local.functions_with_defaults)) > 0
    error_message = "A valid SAM template must still yield Lambda functions"
  }
}
