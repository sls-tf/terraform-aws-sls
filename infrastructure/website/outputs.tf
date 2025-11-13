output "website_url" {
  description = "URL of the deployed website"
  value       = "https://${var.domain_name}"
}

output "staging_url" {
  description = "URL of the staging website"
  value       = "https://sls-tf-staging.s3.amazonaws.com"
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.website.id
}

output "cloudfront_distribution_id_staging" {
  description = "CloudFront distribution ID for staging"
  value       = aws_cloudfront_distribution.website_staging.id
}

output "s3_bucket_name" {
  description = "S3 bucket name for the website"
  value       = aws_s3_bucket.website.bucket
}

output "s3_bucket_name_staging" {
  description = "S3 bucket name for staging"
  value       = aws_s3_bucket.website_staging.bucket
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN"
  value       = aws_acm_certificate_validation.website.certificate_arn
}