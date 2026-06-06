# ============================================================================
# CloudFront Lambda@Edge Resource Generation Tests (Roadmap #12)
# ============================================================================
#
# LocalStack Compatibility: PARTIAL
# These tests validate CloudFront distribution creation from cloudFront events.
# CloudFront support in LocalStack requires Pro edition.

mock_provider "aws" {}

variables {
  use_localstack      = false
  localstack_endpoint = "http://localhost:4566"
}

run "lambda_edge_single_distribution_created" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-simple.yml"
  }

  assert {
    condition     = length(aws_cloudfront_distribution.lambda_edge) == 1
    error_message = "Should create 1 Lambda@Edge distribution, found ${length(aws_cloudfront_distribution.lambda_edge)}"
  }

  assert {
    condition     = contains(keys(aws_cloudfront_distribution.lambda_edge), "default")
    error_message = "Should create distribution with key 'default'"
  }

  assert {
    condition     = aws_cloudfront_distribution.lambda_edge["default"].enabled == true
    error_message = "Lambda@Edge distribution should be enabled"
  }
}

run "lambda_edge_origin_from_string_url" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-simple.yml"
  }

  assert {
    condition     = anytrue([for origin in aws_cloudfront_distribution.lambda_edge["default"].origin : origin.domain_name == "www.example.com"])
    error_message = "Should set origin domain from string URL (without protocol prefix)"
  }
}

run "lambda_edge_s3_origin" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-s3-origin.yml"
  }

  assert {
    condition     = length(aws_cloudfront_distribution.lambda_edge) == 1
    error_message = "Should create 1 Lambda@Edge distribution for S3 origin"
  }

  assert {
    condition     = anytrue([for origin in aws_cloudfront_distribution.lambda_edge["default"].origin : length(origin.s3_origin_config) == 1])
    error_message = "Should create S3 origin config for S3 origin type"
  }

  assert {
    condition     = anytrue([for origin in aws_cloudfront_distribution.lambda_edge["default"].origin : anytrue([for s3c in origin.s3_origin_config : s3c.origin_access_identity != ""])])
    error_message = "Should set OriginAccessIdentity from S3OriginConfig"
  }
}

run "lambda_edge_viewer_protocol_policy" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-simple.yml"
  }

  assert {
    condition     = aws_cloudfront_distribution.lambda_edge["default"].default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https"
    error_message = "Should set viewer_protocol_policy from behavior config"
  }
}

run "lambda_edge_association_in_default_behavior" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-simple.yml"
  }

  assert {
    condition     = length(aws_cloudfront_distribution.lambda_edge["default"].default_cache_behavior[0].lambda_function_association) == 1
    error_message = "Should have 1 lambda_function_association in default cache behavior"
  }

  assert {
    condition     = one([for a in aws_cloudfront_distribution.lambda_edge["default"].default_cache_behavior[0].lambda_function_association : a.event_type]) == "viewer-request"
    error_message = "Lambda@Edge association should have viewer-request event type"
  }
}

run "lambda_edge_ordered_behavior_for_path_pattern" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-multi.yml"
  }

  assert {
    condition     = length(aws_cloudfront_distribution.lambda_edge["default"].ordered_cache_behavior) == 1
    error_message = "Should create 1 ordered cache behavior for pathPattern"
  }

  assert {
    condition     = aws_cloudfront_distribution.lambda_edge["default"].ordered_cache_behavior[0].path_pattern == "/api/*"
    error_message = "Ordered behavior should use the pathPattern from the event"
  }

  assert {
    condition     = one([for a in aws_cloudfront_distribution.lambda_edge["default"].ordered_cache_behavior[0].lambda_function_association : a.event_type]) == "origin-request"
    error_message = "Ordered behavior Lambda@Edge should have origin-request event type"
  }
}

run "lambda_edge_lambda_publish_enabled" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-simple.yml"
  }

  assert {
    condition     = aws_lambda_function.functions["viewerRequest"].publish == true
    error_message = "Lambda function with cloudFront event should have publish=true"
  }
}

run "lambda_edge_iam_trust_policy" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-simple.yml"
  }

  assert {
    condition     = can(regex("edgelambda\\.amazonaws\\.com", aws_iam_role.lambda_execution["viewerRequest"].assume_role_policy))
    error_message = "IAM role for Lambda@Edge function should trust edgelambda.amazonaws.com"
  }
}

run "lambda_edge_geo_restriction_none" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-simple.yml"
  }

  assert {
    condition     = aws_cloudfront_distribution.lambda_edge["default"].restrictions[0].geo_restriction[0].restriction_type == "none"
    error_message = "Distribution should have no geo restrictions by default"
  }
}

run "lambda_edge_default_viewer_certificate" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-simple.yml"
  }

  assert {
    condition     = aws_cloudfront_distribution.lambda_edge["default"].viewer_certificate[0].cloudfront_default_certificate == true
    error_message = "Distribution should use default CloudFront certificate"
  }
}

run "lambda_edge_tags" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-simple.yml"
  }

  assert {
    condition     = aws_cloudfront_distribution.lambda_edge["default"].tags["ManagedBy"] == "sls.tf"
    error_message = "Distribution should be tagged with ManagedBy=sls.tf"
  }

  assert {
    condition     = aws_cloudfront_distribution.lambda_edge["default"].tags["Environment"] == "dev"
    error_message = "Distribution should be tagged with environment stage"
  }
}

run "lambda_edge_outputs" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-edge-simple.yml"
  }

  assert {
    condition     = length(output.lambda_edge_distribution_ids) == 1
    error_message = "Should output 1 Lambda@Edge distribution ID"
  }

  assert {
    condition     = length(output.lambda_edge_distribution_domain_names) == 1
    error_message = "Should output 1 Lambda@Edge distribution domain name"
  }

  assert {
    condition     = output.lambda_edge_distribution_count == 1
    error_message = "Should output Lambda@Edge distribution count of 1"
  }
}

run "lambda_edge_no_distributions_without_events" {
  command = plan

  variables {
    config_path = "tests/fixtures/valid-full.yml"
  }

  assert {
    condition     = length(aws_cloudfront_distribution.lambda_edge) == 0
    error_message = "Should not create Lambda@Edge distributions when no cloudFront events"
  }
}
