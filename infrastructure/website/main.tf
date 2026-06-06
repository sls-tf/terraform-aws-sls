# ============================================================================
# Terraform configuration for sls.tf website infrastructure
# ============================================================================
# Simple S3 bucket deployment for CloudFlare origin
# CloudFlare handles CDN, SSL, and DNS

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }

  # Uncomment and configure for remote state storage after initial setup
  # backend "s3" {
  #   bucket         = "sls-tf-terraform-state"
  #   key            = "website/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "sls-tf-terraform-locks"
  # }
}

# Default provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "sls.tf"
      ManagedBy   = "Terraform"
      Environment = var.environment
      Component   = "website"
    }
  }
}

# ============================================================================
# S3 Bucket for Website Hosting
# ============================================================================

resource "aws_s3_bucket" "website" {
  bucket = var.bucket_name

  tags = {
    Name        = "sls.tf-website"
    Environment = var.environment
  }
}

# Enable versioning for rollback capability
resource "aws_s3_bucket_versioning" "website" {
  bucket = aws_s3_bucket.website.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Public access configuration (CloudFlare will access via public URL)
resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Bucket policy to allow public read access
resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.website.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.website]
}

# Website configuration
resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "404.html"
  }
}

# ============================================================================
# IAM User for GitHub Actions Deployment
# ============================================================================

resource "aws_iam_user" "github_deployer" {
  name = "sls-tf-website-deployer"
  path = "/service-accounts/"

  tags = {
    Name        = "GitHub Actions Deployer"
    Environment = var.environment
  }
}

resource "aws_iam_user_policy" "github_deployer" {
  name = "s3-website-deployment"
  user = aws_iam_user.github_deployer.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.website.arn,
          "${aws_s3_bucket.website.arn}/*"
        ]
      }
    ]
  })
}

# Access key for GitHub Actions
resource "aws_iam_access_key" "github_deployer" {
  user = aws_iam_user.github_deployer.name
}
