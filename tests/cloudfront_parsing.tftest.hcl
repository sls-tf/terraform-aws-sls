# ============================================================================
# CloudFront Distribution Parsing Tests (Roadmap #12)
# ============================================================================
#
# LocalStack Compatibility: FULL
# These tests validate CloudFront distribution parsing from serverless.yml
# resources section. They test locals without creating actual resources.

# Dual-mode provider configuration
provider "aws" {
  region                      = "us-east-1"
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack

  endpoints {
    cloudfront = var.use_localstack ? var.localstack_endpoint : null
    s3         = var.use_localstack ? var.localstack_endpoint : null
  }
}

variables {
  use_localstack      = false
  localstack_endpoint = "http://localhost:4566"
}

run "cloudfront_distribution_detection" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-distribution.yml"
  }

  # Should detect CloudFront distributions
  assert {
    condition     = length(local.cloudfront_distributions) == 2
    error_message = "Should detect 2 CloudFront distributions, found ${length(local.cloudfront_distributions)}"
  }

  assert {
    condition     = contains(keys(local.cloudfront_distributions), "WebAppCloudFrontDistribution")
    error_message = "Should detect WebAppCloudFrontDistribution"
  }

  assert {
    condition     = contains(keys(local.cloudfront_distributions), "ApiCloudFrontDistribution")
    error_message = "Should detect ApiCloudFrontDistribution"
  }
}

run "cloudfront_origin_parsing" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-distribution.yml"
  }

  # Verify origin parsing for custom origin
  assert {
    condition     = length(try(local.cloudfront_distributions["WebAppCloudFrontDistribution"].Properties.DistributionConfig.Origins, [])) == 1
    error_message = "WebApp distribution should have 1 origin"
  }

  assert {
    condition     = try(local.cloudfront_distributions["WebAppCloudFrontDistribution"].Properties.DistributionConfig.Origins[0].Id, "") == "WebApp"
    error_message = "Origin ID should be WebApp"
  }

  assert {
    condition     = try(local.cloudfront_distributions["WebAppCloudFrontDistribution"].Properties.DistributionConfig.Origins[0].CustomOriginConfig.OriginProtocolPolicy, "") == "https-only"
    error_message = "Origin protocol policy should be https-only"
  }
}

run "cloudfront_cache_behavior_parsing" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-distribution.yml"
  }

  # Verify default cache behavior parsing
  assert {
    condition     = length(try(local.cloudfront_distributions["WebAppCloudFrontDistribution"].Properties.DistributionConfig.DefaultCacheBehavior.AllowedMethods, [])) == 7
    error_message = "WebApp distribution should allow 7 HTTP methods"
  }

  assert {
    condition     = try(local.cloudfront_distributions["WebAppCloudFrontDistribution"].Properties.DistributionConfig.DefaultCacheBehavior.ViewerProtocolPolicy, "") == "redirect-to-https"
    error_message = "Viewer protocol policy should be redirect-to-https"
  }

  assert {
    condition     = try(local.cloudfront_distributions["WebAppCloudFrontDistribution"].Properties.DistributionConfig.DefaultCacheBehavior.Compress, false) == true
    error_message = "Compression should be enabled"
  }
}

run "cloudfront_error_responses_parsing" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-distribution.yml"
  }

  # Verify custom error responses
  assert {
    condition     = length(try(local.cloudfront_distributions["WebAppCloudFrontDistribution"].Properties.DistributionConfig.CustomErrorResponses, [])) == 2
    error_message = "WebApp distribution should have 2 custom error responses"
  }

  assert {
    condition     = try(local.cloudfront_distributions["WebAppCloudFrontDistribution"].Properties.DistributionConfig.CustomErrorResponses[0].ErrorCode, 0) == 404
    error_message = "First error response should be for 404"
  }

  assert {
    condition     = try(local.cloudfront_distributions["WebAppCloudFrontDistribution"].Properties.DistributionConfig.CustomErrorResponses[0].ResponsePagePath, "") == "/index.html"
    error_message = "404 should redirect to /index.html"
  }
}

run "cloudfront_viewer_certificate_parsing" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-distribution.yml"
  }

  # Verify viewer certificate config - default certificate
  assert {
    condition     = try(local.cloudfront_distributions["WebAppCloudFrontDistribution"].Properties.DistributionConfig.ViewerCertificate.CloudFrontDefaultCertificate, false) == true
    error_message = "WebApp should use CloudFront default certificate"
  }

  # Verify viewer certificate config - custom ACM certificate
  assert {
    condition     = can(regex("^arn:aws:acm:", try(local.cloudfront_distributions["ApiCloudFrontDistribution"].Properties.DistributionConfig.ViewerCertificate.AcmCertificateArn, "")))
    error_message = "API distribution should have ACM certificate ARN"
  }

  assert {
    condition     = try(local.cloudfront_distributions["ApiCloudFrontDistribution"].Properties.DistributionConfig.ViewerCertificate.MinimumProtocolVersion, "") == "TLSv1.2_2021"
    error_message = "API distribution should use TLSv1.2_2021 protocol"
  }
}

run "cloudfront_s3_origin_config" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-s3.yml"
  }

  # Verify S3 origin configuration
  assert {
    condition     = length(local.cloudfront_distributions) == 1
    error_message = "Should detect 1 CloudFront distribution"
  }

  assert {
    condition     = try(local.cloudfront_distributions["StaticSiteDistribution"].Properties.DistributionConfig.Origins[0].S3OriginConfig.OriginAccessIdentity, "") != ""
    error_message = "S3 origin should have OriginAccessIdentity configured"
  }

  assert {
    condition     = try(local.cloudfront_distributions["StaticSiteDistribution"].Properties.DistributionConfig.DefaultRootObject, "") == "index.html"
    error_message = "Should have index.html as default root object"
  }
}

run "cloudfront_advanced_features" {
  command = plan

  variables {
    config_path = "tests/fixtures/cloudfront-distribution.yml"
  }

  # Verify WAF integration
  assert {
    condition     = can(regex("^arn:aws:wafv2:", try(local.cloudfront_distributions["ApiCloudFrontDistribution"].Properties.DistributionConfig.WebACLId, "")))
    error_message = "API distribution should have WAF WebACL configured"
  }

  # Verify logging configuration
  assert {
    condition     = try(local.cloudfront_distributions["ApiCloudFrontDistribution"].Properties.DistributionConfig.Logging.Bucket, "") == "my-logs.s3.amazonaws.com"
    error_message = "API distribution should have logging bucket configured"
  }

  # Verify geo restrictions
  assert {
    condition     = try(local.cloudfront_distributions["ApiCloudFrontDistribution"].Properties.DistributionConfig.Restrictions.GeoRestriction.RestrictionType, "") == "whitelist"
    error_message = "API distribution should have geo whitelist configured"
  }

  assert {
    condition     = length(try(local.cloudfront_distributions["ApiCloudFrontDistribution"].Properties.DistributionConfig.Restrictions.GeoRestriction.Locations, [])) == 3
    error_message = "API distribution should have 3 whitelisted countries"
  }

  # Verify aliases
  assert {
    condition     = length(try(local.cloudfront_distributions["ApiCloudFrontDistribution"].Properties.DistributionConfig.Aliases, [])) == 1
    error_message = "API distribution should have 1 alias"
  }
}
