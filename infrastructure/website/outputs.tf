# ============================================================================
# Outputs for sls.tf website infrastructure
# ============================================================================

output "s3_bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.website.id
}

output "s3_bucket_website_endpoint" {
  description = "S3 website endpoint - use this as CloudFlare origin"
  value       = aws_s3_bucket_website_configuration.website.website_endpoint
}

output "s3_bucket_website_domain" {
  description = "S3 website domain"
  value       = aws_s3_bucket_website_configuration.website.website_domain
}

output "github_deployer_access_key_id" {
  description = "AWS Access Key ID for GitHub Actions (add to GitHub secrets)"
  value       = aws_iam_access_key.github_deployer.id
}

output "github_deployer_secret_access_key" {
  description = "AWS Secret Access Key for GitHub Actions (add to GitHub secrets)"
  value       = aws_iam_access_key.github_deployer.secret
  sensitive   = true
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.website.arn
}
