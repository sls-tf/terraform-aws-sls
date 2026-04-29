# ============================================================================
# CloudFront Lambda@Edge Distributions (Roadmap #12)
# Creates CloudFront distributions from cloudFront function events.
#
# The Serverless Framework cloudFront event type attaches Lambda functions to
# CloudFront as Lambda@Edge. This file generates aws_cloudfront_distribution
# resources from those events.
#
# Requirements enforced by validation in locals.tf:
#   - eventType: viewer-request, viewer-response, origin-request, origin-response
#   - viewer-side functions: timeout <= 5s, memorySize <= 128 MB
#   - origin-side functions: timeout <= 30s
#   - Lambda functions must have publish=true (set automatically in main.tf)
#   - Lambda@Edge requires functions deployed in us-east-1
# ============================================================================

resource "aws_cloudfront_distribution" "lambda_edge" {
  for_each = local.cloudfront_lambda_edge_distributions

  enabled = true
  comment = "Lambda@Edge distribution ${each.key == "default" ? "for ${try(local.parsed_config_resolved.service, "unknown")}-${local.provider_with_defaults.stage}" : each.key} - managed by sls.tf"

  # Primary origin derived from the first event in the distribution group.
  # Additional origins in a group must share the same primary domain.
  origin {
    domain_name = each.value.primary_origin.domain_name
    origin_id   = each.value.primary_origin.origin_id

    dynamic "s3_origin_config" {
      for_each = each.value.primary_origin.is_s3 ? [1] : []
      content {
        origin_access_identity = each.value.primary_origin.oai
      }
    }

    dynamic "custom_origin_config" {
      for_each = !each.value.primary_origin.is_s3 ? [1] : []
      content {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = each.value.primary_origin.protocol
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  # Default cache behavior — Lambda@Edge associations for events without pathPattern
  default_cache_behavior {
    target_origin_id       = each.value.primary_origin.origin_id
    allowed_methods        = try(each.value.default_events[0].behavior.AllowedMethods, ["GET", "HEAD"])
    cached_methods         = try(each.value.default_events[0].behavior.CachedMethods, ["GET", "HEAD"])
    viewer_protocol_policy = try(each.value.default_events[0].behavior.ViewerProtocolPolicy, "redirect-to-https")
    compress               = try(each.value.default_events[0].behavior.Compress, false)
    min_ttl                = try(each.value.default_events[0].behavior.MinTTL, 0)
    default_ttl            = try(each.value.default_events[0].behavior.DefaultTTL, 86400)
    max_ttl                = try(each.value.default_events[0].behavior.MaxTTL, 31536000)

    forwarded_values {
      query_string = try(each.value.default_events[0].behavior.ForwardedValues.QueryString, false)
      headers      = try(each.value.default_events[0].behavior.ForwardedValues.Headers, [])
      cookies {
        forward           = try(each.value.default_events[0].behavior.ForwardedValues.Cookies.Forward, "none")
        whitelisted_names = try(each.value.default_events[0].behavior.ForwardedValues.Cookies.WhitelistedNames, [])
      }
    }

    dynamic "lambda_function_association" {
      for_each = each.value.default_events
      content {
        event_type   = lambda_function_association.value.event_type
        lambda_arn   = aws_lambda_function.functions[lambda_function_association.value.function_name].qualified_arn
        include_body = lambda_function_association.value.include_body
      }
    }
  }

  # Ordered cache behaviors — one per unique pathPattern, with Lambda@Edge associations
  dynamic "ordered_cache_behavior" {
    for_each = each.value.ordered_behaviors
    content {
      path_pattern           = ordered_cache_behavior.key
      target_origin_id       = each.value.primary_origin.origin_id
      allowed_methods        = try(ordered_cache_behavior.value[0].behavior.AllowedMethods, ["GET", "HEAD"])
      cached_methods         = try(ordered_cache_behavior.value[0].behavior.CachedMethods, ["GET", "HEAD"])
      viewer_protocol_policy = try(ordered_cache_behavior.value[0].behavior.ViewerProtocolPolicy, "redirect-to-https")
      compress               = try(ordered_cache_behavior.value[0].behavior.Compress, false)
      min_ttl                = try(ordered_cache_behavior.value[0].behavior.MinTTL, 0)
      default_ttl            = try(ordered_cache_behavior.value[0].behavior.DefaultTTL, 86400)
      max_ttl                = try(ordered_cache_behavior.value[0].behavior.MaxTTL, 31536000)

      forwarded_values {
        query_string = try(ordered_cache_behavior.value[0].behavior.ForwardedValues.QueryString, false)
        headers      = try(ordered_cache_behavior.value[0].behavior.ForwardedValues.Headers, [])
        cookies {
          forward           = try(ordered_cache_behavior.value[0].behavior.ForwardedValues.Cookies.Forward, "none")
          whitelisted_names = try(ordered_cache_behavior.value[0].behavior.ForwardedValues.Cookies.WhitelistedNames, [])
        }
      }

      dynamic "lambda_function_association" {
        for_each = ordered_cache_behavior.value
        content {
          event_type   = lambda_function_association.value.event_type
          lambda_arn   = aws_lambda_function.functions[lambda_function_association.value.function_name].qualified_arn
          include_body = lambda_function_association.value.include_body
        }
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name        = each.key == "default" ? "${try(local.parsed_config_resolved.service, "unknown")}-${local.provider_with_defaults.stage}" : each.key
    ManagedBy   = "sls.tf"
    Environment = local.provider_with_defaults.stage
  }
}

# Lambda invoke permission for CloudFront (Lambda@Edge replication)
# CloudFront requires permission to invoke the function across all regions
resource "aws_lambda_permission" "cloudfront_edge" {
  for_each = {
    for event in local.cloudfront_events_raw :
    event.event_key => event
    if !contains(keys(local.cloudfront_distributions), event.distribution)
  }

  statement_id  = "AllowCloudFrontInvoke-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.functions[each.value.function_name].function_name
  principal     = "edgelambda.amazonaws.com"
  qualifier     = aws_lambda_function.functions[each.value.function_name].version
}
