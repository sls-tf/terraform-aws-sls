# Terraform configuration for sls.tf website infrastructure
# This is separate from the main sls.tf module and handles only the static website

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  # Backend configuration (optional)
  backend "s3" {
    bucket = "sls-tf-website-terraform-state"
    key    = "website-infrastructure/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "sls.tf"
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "website"
    }
  }
}

# Generate random suffix for unique resource names
resource "random_pet" "suffix" {
  length = 2
}

# S3 bucket for website hosting (production)
resource "aws_s3_bucket" "website" {
  bucket = var.domain_name

  tags = {
    Name = "sls.tf-website-bucket"
  }
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "website" {
  bucket = aws_s3_bucket.website.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block (we'll manage access via CloudFront)
resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket for website hosting (staging)
resource "aws_s3_bucket" "website_staging" {
  bucket = "sls-tf-staging"

  tags = {
    Name = "sls.tf-staging-bucket"
  }
}

resource "aws_s3_bucket_versioning" "website_staging" {
  bucket = aws_s3_bucket.website_staging.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "website_staging" {
  bucket = aws_s3_bucket.website_staging.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "website_staging" {
  bucket = aws_s3_bucket.website_staging.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACM certificate for SSL
resource "aws_acm_certificate" "website" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  tags = {
    Name = "sls.tf-ssl-certificate"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# DNS validation for ACM certificate
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.website.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.route53_zone_id
}

# Wait for certificate validation
resource "aws_acm_certificate_validation" "website" {
  certificate_arn         = aws_acm_certificate.website.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# CloudFront distribution (production)
resource "aws_cloudfront_distribution" "website" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100" # US, Canada, Europe

  origin {
    domain_name = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.website.bucket

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.website.cloudfront_access_identity_path
    }
  }

  # Cache behavior with security headers
  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = aws_s3_bucket.website.bucket
    compress              = true
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400

    dynamic "function_association" {
      for_each = var.environment == "production" ? [1] : []
      content {
        event_type   = "viewer-response"
        function_arn = aws_cloudfront_function.security_headers[0].arn
      }
    }
  }

  # Security headers function
  dynamic "function_association" {
    for_each = var.environment == "production" ? [1] : []
    content {
      event_type   = "viewer-response"
      function_arn = aws_cloudfront_function.security_headers[0].arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.environment != "production"
    acm_certificate_arn            = var.environment == "production" ? aws_acm_certificate_validation.website.certificate_arn : null
    ssl_support_method             = var.environment == "production" ? "sni-only" : null
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  tags = {
    Name = "sls.tf-cloudfront-distribution"
  }
}

# CloudFront function for security headers
resource "aws_cloudfront_function" "security_headers" {
  count    = var.environment == "production" ? 1 : 0
  name     = "sls-tf-security-headers"
  runtime  = "cloudfront-js-1.0"
  code     = file("${path.module}/security-headers.js")
  comment  = "Add security headers to responses"
  publish  = true
}

# CloudFront Origin Access Identity
resource "aws_cloudfront_origin_access_identity" "website" {
  comment = "sls.tf website OAI"
}

# S3 bucket policy for CloudFront access
resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.website.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.website.arn
          }
        }
      }
    ]
  })
}

# CloudFront distribution (staging)
resource "aws_cloudfront_distribution" "website_staging" {
  enabled             = true
  is_ipv6_enabled     = false # Save costs on staging
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  origin {
    domain_name = aws_s3_bucket.website_staging.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.website_staging.bucket

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.website_staging.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = aws_s3_bucket.website_staging.bucket
    compress              = true
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 0  # No caching for staging
    max_ttl     = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  tags = {
    Name = "sls.tf-staging-cloudfront-distribution"
  }
}

# CloudFront Origin Access Identity for staging
resource "aws_cloudfront_origin_access_identity" "website_staging" {
  comment = "sls.tf website staging OAI"
}

# S3 bucket policy for staging
resource "aws_s3_bucket_policy" "website_staging" {
  bucket = aws_s3_bucket.website_staging.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.website_staging.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.website_staging.arn
          }
        }
      }
    ]
  })
}

# Route 53 records (only for production)
resource "aws_route53_record" "website" {
  count   = var.environment == "production" ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id               = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}

# Route 53 record for staging (using CloudFront domain)
resource "aws_route53_record" "website_staging" {
  zone_id = var.route53_zone_id
  name    = "staging.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [aws_cloudfront_distribution.website_staging.domain_name]
}

# Terraform state bucket (for backend)
resource "aws_s3_bucket" "terraform_state" {
  bucket = "sls-tf-website-terraform-state"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    Name = "sls.tf-website-terraform-state"
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for Terraform state locking
resource "aws_dynamodb_table" "terraform_lock" {
  name         = "sls-tf-website-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "sls.tf-website-terraform-locks"
  }
}