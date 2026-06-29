# Regression: a SAM preprocessor failure (scripts/sam-preprocessor.js returning
# {content:"", error:...}) must FAIL LOUDLY with the real error, never silently
# produce a zero-resource module. Previously the error was coalesced to null /
# swallowed and only surfaced far downstream (e.g. an aws_lambda_permission
# "Function not found" in a consuming module). config_validation now checks the
# PLAN-KNOWN structure + condition-params reads (sam-parser.tf:sam_preprocessor_errors).

mock_provider "aws" {}

provider "null" {}

variables {
  config_format = "sam"
}

# Structurally malformed template: the preprocessor's YAML load throws. Must abort
# at plan with the specific preprocessing error, not a cryptic "Invalid for_each".
run "malformed_sam_fails_loudly" {
  command = plan

  variables {
    config_path = "tests/fixtures/sam-malformed.yaml"
  }

  expect_failures = [
    resource.null_resource.config_validation,
  ]
}

# Empty template file: the resolved/structure reads error
# ("Cannot read properties of undefined (reading 'Parameters')").
run "empty_sam_file_fails_loudly" {
  command = plan

  variables {
    config_path = "tests/fixtures/sam-empty-file.yaml"
  }

  expect_failures = [
    resource.null_resource.config_validation,
  ]
}

# A valid SAM template must still parse to its functions (guards against the
# null-safety fallback masking a healthy template).
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
