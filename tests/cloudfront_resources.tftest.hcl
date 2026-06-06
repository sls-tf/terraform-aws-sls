# ============================================================================
# CloudFront Distribution Resource Generation Tests (Roadmap #12)
# ============================================================================
#
# LocalStack Compatibility: FULL
# These tests validate CloudFront distribution resource generation from
# serverless.yml CloudFormation resources section.

# Dual-mode provider configuration
mock_provider "aws" {}

variables {
  use_localstack      = false
  localstack_endpoint = "http://localhost:4566"
}

run "cloudfront_basic_resource_generation" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-distribution.yml"
  }

  # Should create CloudFront distributions
  assert {
    condition     = length(aws_cloudfront_distribution.custom) == 2
    error_message = "Should create 2 CloudFront distributions, found ${length(aws_cloudfront_distribution.custom)}"
  }

  assert {
    condition     = contains(keys(aws_cloudfront_distribution.custom), "WebAppCloudFrontDistribution")
    error_message = "Should create WebAppCloudFrontDistribution resource"
  }

  assert {
    condition     = contains(keys(aws_cloudfront_distribution.custom), "ApiCloudFrontDistribution")
    error_message = "Should create ApiCloudFrontDistribution resource"
  }

  # Verify enabled state
  assert {
    condition     = aws_cloudfront_distribution.custom["WebAppCloudFrontDistribution"].enabled == true
    error_message = "WebApp distribution should be enabled"
  }

  assert {
    condition     = aws_cloudfront_distribution.custom["ApiCloudFrontDistribution"].enabled == true
    error_message = "API distribution should be enabled"
  }
}

run "cloudfront_origin_generation" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-distribution.yml"
  }

  # Verify WebApp origin configuration
  assert {
    condition     = length(aws_cloudfront_distribution.custom["WebAppCloudFrontDistribution"].origin) == 1
    error_message = "WebApp distribution should have 1 origin"
  }

  # Verify origin domain name contains stage variable
  assert {
    condition     = anytrue([for origin in aws_cloudfront_distribution.custom["WebAppCloudFrontDistribution"].origin : can(regex("my-cloudfront-webapp-dev\\.s3\\.amazonaws\\.com", origin.domain_name))])
    error_message = "Origin domain should contain resolved stage variable"
  }

  # Verify API origin with custom headers
  assert {
    condition     = length(aws_cloudfront_distribution.custom["ApiCloudFrontDistribution"].origin) == 1
    error_message = "API distribution should have 1 origin"
  }

  assert {
    condition     = anytrue([for origin in aws_cloudfront_distribution.custom["ApiCloudFrontDistribution"].origin : length(origin.custom_header) == 1])
    error_message = "API origin should have 1 custom header"
  }
}

run "cloudfront_cache_behavior_generation" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-distribution.yml"
  }

  # Verify default cache behavior
  assert {
    condition     = length(aws_cloudfront_distribution.custom["WebAppCloudFrontDistribution"].default_cache_behavior) == 1
    error_message = "WebApp distribution should have default cache behavior"
  }

  assert {
    condition     = length(aws_cloudfront_distribution.custom["WebAppCloudFrontDistribution"].default_cache_behavior[0].allowed_methods) == 7
    error_message = "WebApp default cache behavior should allow 7 methods"
  }

  assert {
    condition     = aws_cloudfront_distribution.custom["WebAppCloudFrontDistribution"].default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https"
    error_message = "WebApp should redirect to HTTPS"
  }

  assert {
    condition     = aws_cloudfront_distribution.custom["WebAppCloudFrontDistribution"].default_cache_behavior[0].compress == true
    error_message = "WebApp should enable compression"
  }

  # Verify API cache behavior with query strings
  assert {
    condition     = aws_cloudfront_distribution.custom["ApiCloudFrontDistribution"].default_cache_behavior[0].forwarded_values[0].query_string == true
    error_message = "API distribution should forward query strings"
  }

  assert {
    condition     = length(aws_cloudfront_distribution.custom["ApiCloudFrontDistribution"].default_cache_behavior[0].forwarded_values[0].headers) == 2
    error_message = "API distribution should forward 2 headers"
  }
}

run "cloudfront_certificate_generation" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-distribution.yml"
  }

  # Verify default CloudFront certificate
  assert {
    condition     = length(aws_cloudfront_distribution.custom["WebAppCloudFrontDistribution"].viewer_certificate) == 1
    error_message = "WebApp distribution should have viewer certificate config"
  }

  assert {
    condition     = aws_cloudfront_distribution.custom["WebAppCloudFrontDistribution"].viewer_certificate[0].cloudfront_default_certificate == true
    error_message = "WebApp should use CloudFront default certificate"
  }

  # Verify custom ACM certificate
  assert {
    condition     = can(regex("^arn:aws:acm:", aws_cloudfront_distribution.custom["ApiCloudFrontDistribution"].viewer_certificate[0].acm_certificate_arn))
    error_message = "API distribution should have ACM certificate ARN"
  }

  assert {
    condition     = aws_cloudfront_distribution.custom["ApiCloudFrontDistribution"].viewer_certificate[0].minimum_protocol_version == "TLSv1.2_2021"
    error_message = "API distribution should use TLSv1.2_2021 protocol"
  }

  assert {
    condition     = aws_cloudfront_distribution.custom["ApiCloudFrontDistribution"].viewer_certificate[0].ssl_support_method == "sni-only"
    error_message = "API distribution should use SNI"
  }
}

run "cloudfront_error_responses_generation" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-distribution.yml"
  }

  # Verify custom error responses
  assert {
    condition     = length(aws_cloudfront_distribution.custom["WebAppCloudFrontDistribution"].custom_error_response) == 2
    error_message = "WebApp distribution should have 2 custom error responses"
  }

  # custom_error_response is a set (no addressable index): select by error_code.
  # Check 404 error response
  assert {
    condition     = one([for r in aws_cloudfront_distribution.custom["WebAppCloudFrontDistribution"].custom_error_response : r if r.error_code == 404]).response_code == 200
    error_message = "404 should respond with 200"
  }

  assert {
    condition     = one([for r in aws_cloudfront_distribution.custom["WebAppCloudFrontDistribution"].custom_error_response : r if r.error_code == 404]).response_page_path == "/index.html"
    error_message = "404 should serve /index.html"
  }

  # Check 403 error response exists
  assert {
    condition     = contains([for r in aws_cloudfront_distribution.custom["WebAppCloudFrontDistribution"].custom_error_response : r.error_code], 403)
    error_message = "Second error response should be for 403"
  }
}

run "cloudfront_advanced_features_generation" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-distribution.yml"
  }

  # Verify WAF integration
  assert {
    condition     = can(regex("^arn:aws:wafv2:", aws_cloudfront_distribution.custom["ApiCloudFrontDistribution"].web_acl_id))
    error_message = "API distribution should have WAF WebACL ID"
  }

  # Verify logging configuration
  assert {
    condition     = length(aws_cloudfront_distribution.custom["ApiCloudFrontDistribution"].logging_config) == 1
    error_message = "API distribution should have logging config"
  }

  assert {
    condition     = aws_cloudfront_distribution.custom["ApiCloudFrontDistribution"].logging_config[0].bucket == "my-logs.s3.amazonaws.com"
    error_message = "API distribution should log to correct bucket"
  }

  assert {
    condition     = aws_cloudfront_distribution.custom["ApiCloudFrontDistribution"].logging_config[0].prefix == "cloudfront/"
    error_message = "API distribution should use cloudfront/ prefix"
  }

  assert {
    condition     = aws_cloudfront_distribution.custom["ApiCloudFrontDistribution"].logging_config[0].include_cookies == false
    error_message = "API distribution should not include cookies in logs"
  }
}

run "cloudfront_geo_restrictions_generation" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-distribution.yml"
  }

  # Verify geo restrictions
  assert {
    condition     = length(aws_cloudfront_distribution.custom["ApiCloudFrontDistribution"].restrictions) == 1
    error_message = "API distribution should have restrictions config"
  }

  assert {
    condition     = length(aws_cloudfront_distribution.custom["ApiCloudFrontDistribution"].restrictions[0].geo_restriction) == 1
    error_message = "API distribution should have geo restriction"
  }

  assert {
    condition     = aws_cloudfront_distribution.custom["ApiCloudFrontDistribution"].restrictions[0].geo_restriction[0].restriction_type == "whitelist"
    error_message = "API distribution should have whitelist restriction"
  }

  assert {
    condition     = length(aws_cloudfront_distribution.custom["ApiCloudFrontDistribution"].restrictions[0].geo_restriction[0].locations) == 3
    error_message = "API distribution should whitelist 3 countries"
  }
}

run "cloudfront_aliases_generation" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-distribution.yml"
  }

  # Verify aliases
  assert {
    condition     = length(aws_cloudfront_distribution.custom["ApiCloudFrontDistribution"].aliases) == 1
    error_message = "API distribution should have 1 alias"
  }

  assert {
    condition     = contains(aws_cloudfront_distribution.custom["ApiCloudFrontDistribution"].aliases, "cdn.example.com")
    error_message = "API distribution should have cdn.example.com alias"
  }
}

run "cloudfront_s3_origin_generation" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-s3.yml"
  }

  # Verify S3 origin configuration
  assert {
    condition     = length(aws_cloudfront_distribution.custom) == 1
    error_message = "Should create 1 CloudFront distribution"
  }

  assert {
    condition     = contains(keys(aws_cloudfront_distribution.custom), "StaticSiteDistribution")
    error_message = "Should create StaticSiteDistribution"
  }

  # origin is a set (no addressable index): select the S3 origin by predicate.
  assert {
    condition     = length(one([for o in aws_cloudfront_distribution.custom["StaticSiteDistribution"].origin : o if length(o.s3_origin_config) > 0]).s3_origin_config) == 1
    error_message = "S3 origin should have s3_origin_config"
  }

  assert {
    condition     = one([for o in aws_cloudfront_distribution.custom["StaticSiteDistribution"].origin : o if length(o.s3_origin_config) > 0]).s3_origin_config[0].origin_access_identity != ""
    error_message = "S3 origin should have OriginAccessIdentity"
  }

  assert {
    condition     = aws_cloudfront_distribution.custom["StaticSiteDistribution"].default_root_object == "index.html"
    error_message = "S3 distribution should have index.html as default root object"
  }
}

run "cloudfront_price_class_generation" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-distribution.yml"
  }

  # Verify price class configuration
  assert {
    condition     = aws_cloudfront_distribution.custom["WebAppCloudFrontDistribution"].price_class == "PriceClass_100"
    error_message = "WebApp distribution should use PriceClass_100"
  }

  assert {
    condition     = aws_cloudfront_distribution.custom["ApiCloudFrontDistribution"].price_class == "PriceClass_All"
    error_message = "API distribution should use PriceClass_All"
  }
}

run "cloudfront_tagging" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-distribution.yml"
  }

  # Verify standard tags
  assert {
    condition     = aws_cloudfront_distribution.custom["WebAppCloudFrontDistribution"].tags["ManagedBy"] == "sls.tf"
    error_message = "Distribution should be tagged with ManagedBy=sls.tf"
  }

  assert {
    condition     = aws_cloudfront_distribution.custom["WebAppCloudFrontDistribution"].tags["LogicalId"] == "WebAppCloudFrontDistribution"
    error_message = "Distribution should be tagged with original logical ID"
  }

  assert {
    condition     = aws_cloudfront_distribution.custom["WebAppCloudFrontDistribution"].tags["Environment"] == "dev"
    error_message = "Distribution should be tagged with environment stage"
  }
}

run "cloudfront_output_generation" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-distribution.yml"
  }

  # Verify CloudFront outputs exist
  assert {
    condition     = length(output.custom_cloudfront_distribution_ids) == 2
    error_message = "Should output 2 CloudFront distribution IDs"
  }

  assert {
    condition     = length(output.custom_cloudfront_distribution_arns) == 2
    error_message = "Should output 2 CloudFront distribution ARNs"
  }

  assert {
    condition     = length(output.custom_cloudfront_distribution_domain_names) == 2
    error_message = "Should output 2 CloudFront distribution domain names"
  }
}
