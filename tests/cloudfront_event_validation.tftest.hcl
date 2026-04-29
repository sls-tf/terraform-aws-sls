# ============================================================================
# CloudFront Event Validation Tests (Roadmap #12)
# ============================================================================
#
# LocalStack Compatibility: FULL (no provider credentials required)
# These tests verify validation errors for invalid cloudFront event configs.

provider "null" {}

run "cloudfront_invalid_eventtype_rejected" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-invalid-eventtype.yml"
  }

  expect_failures = [
    null_resource.config_validation
  ]
}

run "cloudfront_viewer_timeout_rejected" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-invalid-timeout.yml"
  }

  expect_failures = [
    null_resource.config_validation
  ]
}

run "cloudfront_viewer_memory_rejected" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-invalid-memory.yml"
  }

  expect_failures = [
    null_resource.config_validation
  ]
}
