# ============================================================================
# CloudFront Event (Lambda@Edge) Parsing Tests (Roadmap #12)
# ============================================================================
#
# LocalStack Compatibility: FULL
# Tests cloudFront event parsing from function definitions.
# Validates locals without creating actual resources.

mock_provider "aws" {}

variables {
  use_localstack      = false
  localstack_endpoint = "http://localhost:4566"
}

run "cloudfront_event_detection" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-simple.yml"
  }

  assert {
    condition     = length(local.cloudfront_events_raw) == 1
    error_message = "Should detect 1 cloudFront event, found ${length(local.cloudfront_events_raw)}"
  }

  assert {
    condition     = local.cloudfront_events_raw[0].function_name == "viewerRequest"
    error_message = "Should detect cloudFront event for viewerRequest function"
  }

  assert {
    condition     = local.cloudfront_events_raw[0].event_type == "viewer-request"
    error_message = "Should parse eventType as viewer-request"
  }

  assert {
    condition     = local.cloudfront_events_raw[0].distribution == "default"
    error_message = "Should default distribution to 'default' when not specified"
  }
}

run "cloudfront_origin_string_parsing" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-simple.yml"
  }

  assert {
    condition     = local.cloudfront_events_raw[0].origin == "https://www.example.com"
    error_message = "Should preserve string origin as-is"
  }
}

run "cloudfront_origin_object_parsing" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-s3-origin.yml"
  }

  assert {
    condition     = length(local.cloudfront_events_raw) == 1
    error_message = "Should detect 1 cloudFront event with object origin"
  }

  assert {
    condition     = try(local.cloudfront_events_raw[0].origin.DomainName, "") == "my-static-site.s3.amazonaws.com"
    error_message = "Should parse DomainName from object origin"
  }

  assert {
    condition     = try(local.cloudfront_events_raw[0].origin.S3OriginConfig.OriginAccessIdentity, "") != ""
    error_message = "Should parse S3OriginConfig from object origin"
  }
}

run "cloudfront_multi_function_parsing" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-multi.yml"
  }

  assert {
    condition     = length(local.cloudfront_events_raw) == 2
    error_message = "Should detect 2 cloudFront events from 2 functions"
  }

  assert {
    condition     = contains([for ev in local.cloudfront_events_raw : ev.function_name], "viewerRequestFn")
    error_message = "Should detect cloudFront event for viewerRequestFn"
  }

  assert {
    condition     = contains([for ev in local.cloudfront_events_raw : ev.function_name], "originRequestFn")
    error_message = "Should detect cloudFront event for originRequestFn"
  }
}

run "cloudfront_path_pattern_parsing" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-multi.yml"
  }

  assert {
    condition     = try([for ev in local.cloudfront_events_raw : ev.path_pattern if ev.function_name == "originRequestFn"][0], null) == "/api/*"
    error_message = "Should parse pathPattern from cloudFront event"
  }

  assert {
    condition     = try([for ev in local.cloudfront_events_raw : ev.path_pattern if ev.function_name == "viewerRequestFn"][0], "missing") == null
    error_message = "Should have null pathPattern when not specified"
  }
}

run "cloudfront_functions_set_detection" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-multi.yml"
  }

  assert {
    condition     = contains(local.functions_with_cloudfront_events, "viewerRequestFn")
    error_message = "Should include viewerRequestFn in functions_with_cloudfront_events"
  }

  assert {
    condition     = contains(local.functions_with_cloudfront_events, "originRequestFn")
    error_message = "Should include originRequestFn in functions_with_cloudfront_events"
  }
}

run "cloudfront_distribution_groups" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-multi.yml"
  }

  assert {
    condition     = contains(keys(local.cloudfront_distribution_groups), "default")
    error_message = "Should create a 'default' distribution group"
  }

  assert {
    condition     = length(local.cloudfront_distribution_groups["default"]) == 2
    error_message = "Default distribution group should have 2 events"
  }
}

run "cloudfront_lambda_edge_distributions_prepared" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-multi.yml"
  }

  assert {
    condition     = contains(keys(local.cloudfront_lambda_edge_distributions), "default")
    error_message = "Should prepare a 'default' distribution for resource creation"
  }

  assert {
    condition     = length(local.cloudfront_lambda_edge_distributions["default"].default_events) == 1
    error_message = "Should have 1 default event (viewerRequestFn without pathPattern)"
  }

  assert {
    condition     = length(local.cloudfront_lambda_edge_distributions["default"].ordered_behaviors) == 1
    error_message = "Should have 1 ordered behavior (originRequestFn with pathPattern)"
  }

  assert {
    condition     = contains(keys(local.cloudfront_lambda_edge_distributions["default"].ordered_behaviors), "/api/*")
    error_message = "Should have ordered behavior for /api/* path pattern"
  }
}

run "cloudfront_validation_invalid_eventtype" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-invalid-eventtype.yml"
  }

  expect_failures = [
    null_resource.config_validation
  ]
}

run "cloudfront_validation_viewer_timeout" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-invalid-timeout.yml"
  }

  expect_failures = [
    null_resource.config_validation
  ]
}

run "cloudfront_validation_viewer_memory" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-invalid-memory.yml"
  }

  expect_failures = [
    null_resource.config_validation
  ]
}
