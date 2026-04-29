# ============================================================================
# AWS SAM Template Validation Tests
# ============================================================================
#
# Tests that invalid SAM templates are rejected with clear error messages.
# Requires LocalStack (make localstack-start) or real AWS credentials.

run "sam_invalid_transform_rejected" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-invalid-transform.yaml"
    config_format = "sam"
  }

  expect_failures = [
    null_resource.config_validation
  ]
}

run "sam_missing_handler_rejected" {
  command = plan

  variables {
    config_path   = "tests/fixtures/sam-missing-handler.yaml"
    config_format = "sam"
  }

  expect_failures = [
    null_resource.config_validation
  ]
}
