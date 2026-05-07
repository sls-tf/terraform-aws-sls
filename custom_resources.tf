# ============================================================================
# Custom Resource Provisioning (Roadmap #9)
# CloudFormation-style resources from serverless.yml resources section
# ============================================================================

# ============================================================================
# S3 Buckets
# ============================================================================

# Base S3 bucket resource
# Maps from CloudFormation AWS::S3::Bucket to aws_s3_bucket
resource "aws_s3_bucket" "custom" {
  for_each = local.s3_buckets

  # Use BucketName property if specified, otherwise generate name
  bucket = try(each.value.Properties.BucketName, "${local.to_snake_case[each.key]}-${local.provider_with_defaults.stage}")

  # Force destroy for easier cleanup (can be made configurable)
  force_destroy = true

  tags = merge(
    {
      Name        = each.key
      ManagedBy   = "sls.tf"
      LogicalId   = each.key
      Environment = local.provider_with_defaults.stage
    },
    # Convert CloudFormation tag format to Terraform map
    try({
      for tag in each.value.Properties.Tags :
      tag.Key => tag.Value
    }, {})
  )

  depends_on = [null_resource.config_validation]
}

# S3 bucket versioning configuration
# Created when VersioningConfiguration exists in properties
resource "aws_s3_bucket_versioning" "custom" {
  for_each = {
    for logical_id, resource in local.s3_buckets :
    logical_id => resource
    if try(resource.Properties.VersioningConfiguration, null) != null
  }

  bucket = aws_s3_bucket.custom[each.key].id

  versioning_configuration {
    status = try(each.value.Properties.VersioningConfiguration.Status, "Disabled")
  }
}

# S3 bucket ACL configuration
# Created when AccessControl property exists
resource "aws_s3_bucket_acl" "custom" {
  for_each = {
    for logical_id, resource in local.s3_buckets :
    logical_id => resource
    if try(resource.Properties.AccessControl, null) != null
  }

  bucket = aws_s3_bucket.custom[each.key].id
  acl    = lower(each.value.Properties.AccessControl)

  depends_on = [aws_s3_bucket.custom]
}

# ============================================================================
# DynamoDB Tables
# ============================================================================

# DynamoDB Table resource
# Maps from CloudFormation AWS::DynamoDB::Table to aws_dynamodb_table
resource "aws_dynamodb_table" "custom" {
  for_each = local.dynamodb_tables

  # Use TableName property if specified, otherwise generate name
  name = try(
    each.value.Properties.TableName,
    "${local.to_snake_case[each.key]}-${local.provider_with_defaults.stage}"
  )

  # Billing mode - default to PROVISIONED if not specified
  billing_mode = try(each.value.Properties.BillingMode, "PROVISIONED")

  # Hash key (required)
  hash_key = try([
    for key in each.value.Properties.KeySchema :
    key.AttributeName if key.KeyType == "HASH"
  ][0], null)

  # Range key (optional)
  range_key = try([
    for key in each.value.Properties.KeySchema :
    key.AttributeName if key.KeyType == "RANGE"
  ][0], null)

  # Attribute definitions (required)
  dynamic "attribute" {
    for_each = try(each.value.Properties.AttributeDefinitions, [])
    content {
      name = attribute.value.AttributeName
      type = attribute.value.AttributeType
    }
  }

  # Provisioned throughput (required for PROVISIONED billing mode)
  read_capacity  = try(each.value.Properties.BillingMode, "PROVISIONED") == "PROVISIONED" ? try(each.value.Properties.ProvisionedThroughput.ReadCapacityUnits, 5) : null
  write_capacity = try(each.value.Properties.BillingMode, "PROVISIONED") == "PROVISIONED" ? try(each.value.Properties.ProvisionedThroughput.WriteCapacityUnits, 5) : null

  # Global Secondary Indexes
  dynamic "global_secondary_index" {
    for_each = try(each.value.Properties.GlobalSecondaryIndexes, [])
    content {
      name            = global_secondary_index.value.IndexName
      hash_key        = global_secondary_index.value.KeySchema[0].AttributeName
      range_key       = try(global_secondary_index.value.KeySchema[1].AttributeName, null)
      projection_type = global_secondary_index.value.Projection.ProjectionType
      read_capacity   = try(each.value.Properties.BillingMode, "PROVISIONED") == "PROVISIONED" ? try(global_secondary_index.value.ProvisionedThroughput.ReadCapacityUnits, 5) : null
      write_capacity  = try(each.value.Properties.BillingMode, "PROVISIONED") == "PROVISIONED" ? try(global_secondary_index.value.ProvisionedThroughput.WriteCapacityUnits, 5) : null
    }
  }

  # Stream specification
  stream_enabled   = try(each.value.Properties.StreamSpecification.StreamEnabled, false)
  stream_view_type = try(each.value.Properties.StreamSpecification.StreamViewType, null)

  # Tags
  tags = merge(
    {
      Name        = each.key
      ManagedBy   = "sls.tf"
      LogicalId   = each.key
      Environment = local.provider_with_defaults.stage
    },
    # Convert CloudFormation tag format to Terraform map
    try({
      for tag in each.value.Properties.Tags :
      tag.Key => tag.Value
    }, {})
  )

  depends_on = [null_resource.config_validation]
}

# ============================================================================
# SNS Topics
# ============================================================================

# SNS Topic resource
# Maps from CloudFormation AWS::SNS::Topic to aws_sns_topic
resource "aws_sns_topic" "custom" {
  for_each = local.sns_topics

  # Use TopicName property if specified, otherwise generate name
  name = try(
    each.value.Properties.TopicName,
    "${local.to_snake_case[each.key]}-${local.provider_with_defaults.stage}"
  )

  # Display name for SMS messages
  display_name = try(each.value.Properties.DisplayName, null)

  # FIFO topic settings
  fifo_topic                  = try(each.value.Properties.FifoTopic, false)
  content_based_deduplication = try(each.value.Properties.ContentBasedDeduplication, false)

  # KMS encryption
  kms_master_key_id = try(each.value.Properties.KmsMasterKeyId, null)

  # Tags
  tags = merge(
    {
      Name        = each.key
      ManagedBy   = "sls.tf"
      LogicalId   = each.key
      Environment = local.provider_with_defaults.stage
    },
    # Convert CloudFormation tag format to Terraform map
    try({
      for tag in each.value.Properties.Tags :
      tag.Key => tag.Value
    }, {})
  )

  depends_on = [null_resource.config_validation]
}

# ============================================================================
# SQS Queues
# ============================================================================

# SQS Queue resource
# Maps from CloudFormation AWS::SQS::Queue to aws_sqs_queue
resource "aws_sqs_queue" "custom" {
  for_each = local.sqs_queues

  # Use QueueName property if specified, otherwise generate name
  name = try(
    each.value.Properties.QueueName,
    "${local.to_snake_case[each.key]}-${local.provider_with_defaults.stage}"
  )

  # FIFO queue settings
  fifo_queue                  = try(each.value.Properties.FifoQueue, false)
  content_based_deduplication = try(each.value.Properties.ContentBasedDeduplication, false)

  # Message retention and delays
  message_retention_seconds  = try(each.value.Properties.MessageRetentionPeriod, 345600)  # 4 days default
  delay_seconds              = try(each.value.Properties.DelaySeconds, 0)
  visibility_timeout_seconds = try(each.value.Properties.VisibilityTimeout, 30)

  # Delivery policy
  receive_wait_time_seconds = try(each.value.Properties.ReceiveMessageWaitTimeSeconds, 0)
  max_message_size          = try(each.value.Properties.MaximumMessageSize, 262144)  # 256 KB default

  # Dead letter queue configuration
  redrive_policy = try(each.value.Properties.RedrivePolicy, null) != null ? jsonencode({
    deadLetterTargetArn = try(each.value.Properties.RedrivePolicy.deadLetterTargetArn, null)
    maxReceiveCount     = try(each.value.Properties.RedrivePolicy.maxReceiveCount, 5)
  }) : null

  # KMS encryption
  kms_master_key_id                 = try(each.value.Properties.KmsMasterKeyId, null)
  kms_data_key_reuse_period_seconds = try(each.value.Properties.KmsDataKeyReusePeriodSeconds, 300)

  # Tags
  tags = merge(
    {
      Name        = each.key
      ManagedBy   = "sls.tf"
      LogicalId   = each.key
      Environment = local.provider_with_defaults.stage
    },
    # Convert CloudFormation tag format to Terraform map
    try({
      for tag in each.value.Properties.Tags :
      tag.Key => tag.Value
    }, {})
  )

  depends_on = [null_resource.config_validation]
}

# ============================================================================
# CloudFront Distributions (Roadmap #12)
# ============================================================================

# CloudFront Distribution resource
# Maps from CloudFormation AWS::CloudFront::Distribution to aws_cloudfront_distribution
resource "aws_cloudfront_distribution" "custom" {
  for_each = local.cloudfront_distributions

  enabled             = try(each.value.Properties.DistributionConfig.Enabled, true)
  is_ipv6_enabled     = try(each.value.Properties.DistributionConfig.IPV6Enabled, true)
  comment             = try(each.value.Properties.DistributionConfig.Comment, "Managed by sls.tf - ${each.key}")
  default_root_object = try(each.value.Properties.DistributionConfig.DefaultRootObject, null)
  price_class         = try(each.value.Properties.DistributionConfig.PriceClass, "PriceClass_All")
  aliases             = try(each.value.Properties.DistributionConfig.Aliases, [])
  web_acl_id          = try(each.value.Properties.DistributionConfig.WebACLId, null)

  # Origins configuration
  dynamic "origin" {
    for_each = try(each.value.Properties.DistributionConfig.Origins, [])
    content {
      domain_name = origin.value.DomainName
      origin_id   = origin.value.Id
      origin_path = try(origin.value.OriginPath, "")

      # S3 origin configuration
      dynamic "s3_origin_config" {
        for_each = try(origin.value.S3OriginConfig, null) != null ? [origin.value.S3OriginConfig] : []
        content {
          origin_access_identity = try(s3_origin_config.value.OriginAccessIdentity, "")
        }
      }

      # Custom origin configuration
      dynamic "custom_origin_config" {
        for_each = try(origin.value.CustomOriginConfig, null) != null ? [origin.value.CustomOriginConfig] : []
        content {
          http_port                = try(custom_origin_config.value.HTTPPort, 80)
          https_port               = try(custom_origin_config.value.HTTPSPort, 443)
          origin_protocol_policy   = try(custom_origin_config.value.OriginProtocolPolicy, "https-only")
          origin_ssl_protocols     = try(custom_origin_config.value.OriginSSLProtocols, ["TLSv1.2"])
          origin_keepalive_timeout = try(custom_origin_config.value.OriginKeepaliveTimeout, 5)
          origin_read_timeout      = try(custom_origin_config.value.OriginReadTimeout, 30)
        }
      }

      # Custom headers
      dynamic "custom_header" {
        for_each = try(origin.value.CustomHeaders, [])
        content {
          name  = custom_header.value.HeaderName
          value = custom_header.value.HeaderValue
        }
      }
    }
  }

  # Default cache behavior
  default_cache_behavior {
    allowed_methods  = try(each.value.Properties.DistributionConfig.DefaultCacheBehavior.AllowedMethods, ["GET", "HEAD"])
    cached_methods   = try(each.value.Properties.DistributionConfig.DefaultCacheBehavior.CachedMethods, ["GET", "HEAD"])
    target_origin_id = try(each.value.Properties.DistributionConfig.DefaultCacheBehavior.TargetOriginId, "")

    forwarded_values {
      query_string = try(each.value.Properties.DistributionConfig.DefaultCacheBehavior.ForwardedValues.QueryString, false)
      headers      = try(each.value.Properties.DistributionConfig.DefaultCacheBehavior.ForwardedValues.Headers, [])

      cookies {
        forward           = try(each.value.Properties.DistributionConfig.DefaultCacheBehavior.ForwardedValues.Cookies.Forward, "none")
        whitelisted_names = try(each.value.Properties.DistributionConfig.DefaultCacheBehavior.ForwardedValues.Cookies.WhitelistedNames, [])
      }
    }

    viewer_protocol_policy = try(each.value.Properties.DistributionConfig.DefaultCacheBehavior.ViewerProtocolPolicy, "redirect-to-https")
    min_ttl                = try(each.value.Properties.DistributionConfig.DefaultCacheBehavior.MinTTL, 0)
    default_ttl            = try(each.value.Properties.DistributionConfig.DefaultCacheBehavior.DefaultTTL, 86400)
    max_ttl                = try(each.value.Properties.DistributionConfig.DefaultCacheBehavior.MaxTTL, 31536000)
    compress               = try(each.value.Properties.DistributionConfig.DefaultCacheBehavior.Compress, false)

    # Lambda function associations
    dynamic "lambda_function_association" {
      for_each = try(each.value.Properties.DistributionConfig.DefaultCacheBehavior.LambdaFunctionAssociations, [])
      content {
        event_type   = lambda_function_association.value.EventType
        lambda_arn   = lambda_function_association.value.LambdaFunctionARN
        include_body = try(lambda_function_association.value.IncludeBody, false)
      }
    }
  }

  # Ordered cache behaviors
  dynamic "ordered_cache_behavior" {
    for_each = try(each.value.Properties.DistributionConfig.CacheBehaviors, [])
    content {
      path_pattern     = ordered_cache_behavior.value.PathPattern
      allowed_methods  = try(ordered_cache_behavior.value.AllowedMethods, ["GET", "HEAD"])
      cached_methods   = try(ordered_cache_behavior.value.CachedMethods, ["GET", "HEAD"])
      target_origin_id = ordered_cache_behavior.value.TargetOriginId

      forwarded_values {
        query_string = try(ordered_cache_behavior.value.ForwardedValues.QueryString, false)
        headers      = try(ordered_cache_behavior.value.ForwardedValues.Headers, [])

        cookies {
          forward           = try(ordered_cache_behavior.value.ForwardedValues.Cookies.Forward, "none")
          whitelisted_names = try(ordered_cache_behavior.value.ForwardedValues.Cookies.WhitelistedNames, [])
        }
      }

      viewer_protocol_policy = try(ordered_cache_behavior.value.ViewerProtocolPolicy, "redirect-to-https")
      min_ttl                = try(ordered_cache_behavior.value.MinTTL, 0)
      default_ttl            = try(ordered_cache_behavior.value.DefaultTTL, 86400)
      max_ttl                = try(ordered_cache_behavior.value.MaxTTL, 31536000)
      compress               = try(ordered_cache_behavior.value.Compress, false)

      # Lambda function associations
      dynamic "lambda_function_association" {
        for_each = try(ordered_cache_behavior.value.LambdaFunctionAssociations, [])
        content {
          event_type   = lambda_function_association.value.EventType
          lambda_arn   = lambda_function_association.value.LambdaFunctionARN
          include_body = try(lambda_function_association.value.IncludeBody, false)
        }
      }
    }
  }

  # Custom error responses
  dynamic "custom_error_response" {
    for_each = try(each.value.Properties.DistributionConfig.CustomErrorResponses, [])
    content {
      error_code            = custom_error_response.value.ErrorCode
      response_code         = try(custom_error_response.value.ResponseCode, null)
      response_page_path    = try(custom_error_response.value.ResponsePagePath, null)
      error_caching_min_ttl = try(custom_error_response.value.ErrorCachingMinTTL, 300)
    }
  }

  # Viewer certificate configuration
  viewer_certificate {
    cloudfront_default_certificate = try(each.value.Properties.DistributionConfig.ViewerCertificate.CloudFrontDefaultCertificate, true)
    acm_certificate_arn            = try(each.value.Properties.DistributionConfig.ViewerCertificate.AcmCertificateArn, null)
    iam_certificate_id             = try(each.value.Properties.DistributionConfig.ViewerCertificate.IamCertificateId, null)
    minimum_protocol_version       = try(each.value.Properties.DistributionConfig.ViewerCertificate.MinimumProtocolVersion, "TLSv1.2_2021")
    ssl_support_method             = try(each.value.Properties.DistributionConfig.ViewerCertificate.SslSupportMethod, null)
  }

  # Restrictions (geo restriction)
  restrictions {
    geo_restriction {
      restriction_type = try(each.value.Properties.DistributionConfig.Restrictions.GeoRestriction.RestrictionType, "none")
      locations        = try(each.value.Properties.DistributionConfig.Restrictions.GeoRestriction.Locations, [])
    }
  }

  # Logging configuration
  dynamic "logging_config" {
    for_each = try(each.value.Properties.DistributionConfig.Logging, null) != null ? [each.value.Properties.DistributionConfig.Logging] : []
    content {
      bucket          = logging_config.value.Bucket
      prefix          = try(logging_config.value.Prefix, "")
      include_cookies = try(logging_config.value.IncludeCookies, false)
    }
  }

  # Tags
  tags = merge(
    {
      Name        = each.key
      ManagedBy   = "sls.tf"
      LogicalId   = each.key
      Environment = local.provider_with_defaults.stage
    },
    # Convert CloudFormation tag format to Terraform map
    try({
      for tag in each.value.Properties.Tags :
      tag.Key => tag.Value
    }, {})
  )

  depends_on = [null_resource.config_validation]
}
