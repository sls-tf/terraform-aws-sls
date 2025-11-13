# S3 Bucket Management Tests
# LocalStack Compatibility: FULL
# Tests for bucket identification, custom properties, and naming resolution
# These tests validate S3 bucket creation and notification configuration

provider "aws" {
  region = "us-east-1"

  # Skip AWS-specific validations when using LocalStack
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack

  # CRITICAL: LocalStack requires S3 path-style access
  s3_use_path_style = var.use_localstack

  # Dynamic endpoints - only populated when use_localstack = true
  dynamic "endpoints" {
    for_each = var.use_localstack ? [1] : []
    content {
      apigateway = var.localstack_endpoint
      dynamodb   = var.localstack_endpoint
      events     = var.localstack_endpoint
      iam        = var.localstack_endpoint
      lambda     = var.localstack_endpoint
      route53    = var.localstack_endpoint
      s3         = var.localstack_endpoint
      sns        = var.localstack_endpoint
      sqs        = var.localstack_endpoint
      sts        = var.localstack_endpoint
    }
  }
}

run "test_new_bucket_identification" {
  command = plan

  variables {
    config_path   = "tests/fixtures/s3-shorthand.yml"
    config_format = "yaml"
  }

  # Verify new buckets are identified for creation (existing: false)
  assert {
    condition     = length(keys(local.s3_buckets_to_create)) == 1
    error_message = "Expected 1 bucket to be created, got ${length(keys(local.s3_buckets_to_create))}"
  }

  assert {
    condition     = contains(keys(local.s3_buckets_to_create), "photos")
    error_message = "Expected 'photos' bucket to be in creation list"
  }
}

run "test_existing_bucket_handling" {
  command = plan

  variables {
    config_path   = "tests/fixtures/s3-existing-bucket.yml"
    config_format = "yaml"
  }

  # Verify existing buckets are excluded from creation list
  assert {
    condition     = length(keys(local.s3_buckets_to_create)) == 0
    error_message = "Expected 0 buckets to be created for existing bucket, got ${length(keys(local.s3_buckets_to_create))}"
  }

  assert {
    condition     = length(local.s3_events_normalized) == 1
    error_message = "Expected 1 S3 event to be parsed"
  }

  assert {
    condition     = local.s3_events_normalized[0].existing == true
    error_message = "Expected existing flag to be true"
  }
}

run "test_custom_bucket_name_resolution" {
  command = plan

  variables {
    config_path   = "tests/fixtures/s3-custom-properties.yml"
    config_format = "yaml"
  }

  # Verify custom bucket names resolved from provider.s3 section
  assert {
    condition     = local.s3_buckets_to_create["archiveBucket"].name == "my-archive-bucket-prod-unique"
    error_message = "Expected custom bucket name 'my-archive-bucket-prod-unique', got ${try(local.s3_buckets_to_create["archiveBucket"].name, "none")}"
  }
}

run "test_bucket_name_fallback_to_key" {
  command = plan

  variables {
    config_path   = "tests/fixtures/s3-shorthand.yml"
    config_format = "yaml"
  }

  # Verify bucket name defaults to bucket key when no custom name
  assert {
    condition     = local.s3_buckets_to_create["photos"].name == "photos"
    error_message = "Expected bucket name to fallback to key 'photos', got ${try(local.s3_buckets_to_create["photos"].name, "none")}"
  }
}

run "test_multiple_functions_same_bucket" {
  command = plan

  variables {
    config_path   = "tests/fixtures/s3-multiple-functions.yml"
    config_format = "yaml"
  }

  # Verify same bucket only created once when multiple functions reference it
  assert {
    condition     = length(keys(local.s3_buckets_to_create)) == 1
    error_message = "Expected 1 bucket to be created (shared), got ${length(keys(local.s3_buckets_to_create))}"
  }

  assert {
    condition     = length(local.s3_events_normalized) == 2
    error_message = "Expected 2 S3 events from 2 functions, got ${length(local.s3_events_normalized)}"
  }
}
