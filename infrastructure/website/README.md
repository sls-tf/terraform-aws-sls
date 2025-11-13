# sls.tf Website Infrastructure

This directory contains the Terraform configuration for deploying the sls.tf documentation website infrastructure, completely separate from the main sls.tf module.

## Architecture

The website infrastructure consists of:

- **S3 Buckets**: Static website hosting for production and staging
- **CloudFront**: CDN with SSL/TLS, security headers, and caching
- **Route 53**: DNS management and domain configuration
- **ACM**: SSL certificate management
- **CI/CD**: GitHub Actions for automated deployment

## Quick Start

### 1. Prerequisites

- Terraform >= 1.0
- AWS CLI configured with appropriate permissions
- Route 53 hosted zone for your domain
- ACM certificate (will be created automatically)

### 2. Configure Variables

Create a `terraform.tfvars` file:

```hcl
aws_region        = "us-east-1"
domain_name       = "sls.tf"
environment       = "production"
route53_zone_id   = "Z1D633PEXAMPLE"
```

### 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Configure GitHub Actions

Add the following secrets to your GitHub repository:

- `AWS_ACCESS_KEY_ID`: AWS access key with S3, CloudFront, and Route 53 permissions
- `AWS_SECRET_ACCESS_KEY`: AWS secret key
- `CLOUDFRONT_DISTRIBUTION_ID_PRODUCTION`: Production CloudFront distribution ID
- `CLOUDFRONT_DISTRIBUTION_ID_STAGING`: Staging CloudFront distribution ID
- `SLACK_WEBHOOK_URL`: (Optional) Slack webhook for deployment notifications

## Infrastructure Details

### Production Environment

#### S3 Bucket
- **Name**: `sls.tf`
- **Features**: Versioning, encryption, public access blocked
- **Access**: Only via CloudFront OAI

#### CloudFront Distribution
- **Domain**: `sls.tf`
- **SSL**: Custom certificate with TLS 1.2+
- **Security**: Security headers, HTTPS redirect
- **Caching**: Optimized for static assets
- **Geo-restriction**: None (global access)

#### Route 53
- **A Record**: `sls.tf` → CloudFront distribution
- **CNAME Record**: `staging.sls.tf` → Staging CloudFront

### Staging Environment

#### S3 Bucket
- **Name**: `sls-tf-staging`
- **Features**: Versioning, encryption
- **Caching**: Disabled (immediate updates)

#### CloudFront Distribution
- **Domain**: CloudFront default domain
- **SSL**: Default CloudFront certificate
- **IPv6**: Disabled (cost optimization)
- **Caching**: Disabled (for testing)

## Security Features

### CloudFront Security Headers
```javascript
{
  "strict-transport-security": "max-age=31536000; includeSubDomains; preload",
  "x-content-type-options": "nosniff",
  "x-frame-options": "DENY",
  "x-xss-protection": "1; mode=block",
  "referrer-policy": "strict-origin-when-cross-origin",
  "permissions-policy": "camera=(), microphone=(), geolocation=(), interest-cohort=()"
}
```

### S3 Security
- Server-side encryption with AES-256
- Versioning enabled for backup and recovery
- Public access blocked, only CloudFront access
- Bucket policies enforce least privilege

### Network Security
- HTTPS-only with TLS 1.2+
- CloudFront provides DDoS protection
- Origin Access Identity (OAI) restricts S3 access
- Security headers at CDN level

## Deployment Process

### Automatic Deployment (Production)
1. Push to `main` branch
2. GitHub Actions workflow triggers
3. Astro website is built
4. Assets uploaded to S3
5. CloudFront cache invalidated
6. DNS updated (if needed)
7. Deployment notifications sent

### Preview Deployment (Staging)
1. Pull request created
2. GitHub Actions workflow triggers
3. Website built and deployed to staging
4. Preview URL available for review
5. Merge to main triggers production deployment

### Manual Deployment
```bash
# Deploy to staging
gh workflow run website-deploy.yml -f environment=staging

# Deploy to production
gh workflow run website-deploy.yml -f environment=production
```

## Monitoring and Maintenance

### Performance Monitoring
- CloudWatch metrics for S3 and CloudFront
- Lighthouse CI audits on deployment
- Real User Monitoring (RUM) data
- Core Web Vitals tracking

### Security Monitoring
- Trivy vulnerability scanning
- Link checking and broken link detection
- SSL certificate monitoring
- Security headers validation

### Cost Optimization
- S3 Intelligent-Tiering
- CloudFront price class optimization
- Staging environment cost controls
- Automatic cleanup of old versions

## Backup and Disaster Recovery

### S3 Versioning
- All file versions retained
- Can restore any previous version
- Protects against accidental deletion

### CloudFront Cache
- Multiple edge locations globally
- Automatic failover capabilities
- DDoS protection included

### Route 53
- DNS-level health checks
- Automatic failover routing
- Global load balancing

## Troubleshooting

### Common Issues

**Website not updating**
- Check CloudFront cache invalidation
- Verify S3 upload completed
- Check DNS propagation

**SSL certificate issues**
- Verify ACM certificate validation
- Check Route 53 CNAME records
- Ensure certificate is attached to CloudFront

**Build failures**
- Check GitHub Actions logs
- Verify Node.js version compatibility
- Check dependency installation

**Permission errors**
- Verify AWS credentials and permissions
- Check S3 bucket policies
- Validate CloudFront OAI configuration

### Debug Commands

```bash
# Check S3 bucket contents
aws s3 ls s3://sls.tf --recursive

# Check CloudFront distribution status
aws cloudfront get-distribution --id DISTRIBUTION_ID

# Invalidate CloudFront cache
aws cloudfront create-invalidation --distribution-id DISTRIBUTION_ID --paths "/*"

# Check ACM certificate status
aws acm describe-certificate --certificate-arn CERT_ARN

# Test website accessibility
curl -I https://sls.tf
```

## Cost Estimates

### Monthly Costs (USD)
- **S3 Storage**: ~$5 (for ~1GB of content)
- **S3 Data Transfer**: ~$10 (for 100GB transfer)
- **CloudFront**: ~$20 (for 500GB transfer)
- **Route 53**: ~$1 (for hosted zone)
- **ACM**: Free (AWS provided certificate)
- **Total**: ~$36/month

### Cost Optimization Tips
- Use S3 lifecycle policies for old versions
- Optimize CloudFront price class based on audience
- Compress images and assets
- Enable CloudFront compression
- Monitor usage regularly

## Security Best Practices

### Regular Reviews
- Review AWS IAM policies quarterly
- Update security headers as needed
- Monitor access logs and patterns
- Keep dependencies updated

### Compliance
- GDPR compliance considerations
- Security headers implementation
- Data retention policies
- Access logging and monitoring

### Automation
- Automated security scanning
- Regular dependency updates
- Infrastructure as code reviews
- Continuous compliance checks

## API Reference

### Terraform Outputs

```hcl
output "website_url" {
  description = "URL of the deployed website"
  value       = "https://sls.tf"
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.website.id
}

output "s3_bucket_name" {
  description = "S3 bucket name for the website"
  value       = aws_s3_bucket.website.bucket
}
```

### Environment Variables

| Variable | Description | Default |
|-----------|-------------|---------|
| `aws_region` | AWS region | `us-east-1` |
| `domain_name` | Website domain | `sls.tf` |
| `environment` | Environment | `production` |
| `route53_zone_id` | Route 53 zone ID | Required |

## Support

- 📖 **Documentation**: [Website Documentation](../../website/)
- 🐛 **Issues**: [GitHub Issues](https://github.com/your-org/sls.tf/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/your-org/sls.tf/discussions)
- 📧 **Email**: support@sls.tf

## License

This website infrastructure is licensed under the same terms as the main sls.tf project.