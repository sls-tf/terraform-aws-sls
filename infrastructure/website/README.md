# sls.tf Website Infrastructure

This directory contains Terraform configuration for deploying the sls.tf documentation website using the [static-website-pipeline](https://github.com/ThomasRedstone/static-website-pipeline) module.

## Overview

The infrastructure provisions:

- **S3 Bucket**: Static website hosting storage
- **CloudFront**: CDN with SSL/TLS termination
- **Route53**: DNS records for the domain
- **ACM Certificate**: SSL/TLS certificate for HTTPS
- **CodePipeline**: Automated CI/CD deployment from GitHub
- **CodeBuild**: Builds the Astro website on each commit

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **AWS CLI** configured with credentials
3. **Terraform** >= 1.0 installed
4. **Route53 Hosted Zone** for your domain
5. **AWS CodeStar Connection** to GitHub (see setup below)

## Setup

### 1. Verify CodeStar Connection

Check if you have an existing CodeStar connection to GitHub:

```bash
aws codestar-connections list-connections --region us-east-1
```

If you don't have one, create it:

```bash
aws codestar-connections create-connection \
  --provider-type GitHub \
  --connection-name main \
  --region us-east-1
```

Then complete the connection in the AWS Console:

1. Go to **Developer Tools > Connections**
2. Find your connection and click **Update pending connection**
3. Authorize GitHub access

**Note**: The default configuration looks for a connection named "main". If yours has a different name, update `codestar_connection_name` in your `terraform.tfvars`.

### 2. Create terraform.tfvars

Copy the example and update with your values:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Then edit `terraform.tfvars`:

```hcl
# terraform.tfvars
git_repository           = "sls-tf/sls.tf"
git_branch               = "main"
codestar_connection_name = "main"  # Name of your CodeStar connection
domain_name              = "sls.tf"
route53_zone_id          = "Z1234567890ABC"  # Your Route53 hosted zone ID
environment              = "production"
```

### 3. Initialize Terraform

```bash
cd infrastructure/website
terraform init
```

### 4. Review the Plan

```bash
terraform plan
```

### 5. Apply the Configuration

```bash
terraform apply
```

## Usage

### Deploy Changes

Once set up, the CodePipeline will automatically:

1. Detect pushes to the `main` branch
2. Pull the latest code from GitHub
3. Build the Astro website (`npm ci && npm run build`)
4. Deploy to S3
5. Invalidate CloudFront cache

### Manual Deployment

You can manually trigger a deployment:

```bash
aws codepipeline start-pipeline-execution \
  --name sls-tf-website-production \
  --region us-east-1
```

### Invalidate CloudFront Cache

To manually invalidate the CloudFront cache:

```bash
# Get the distribution ID from Terraform output
DIST_ID=$(terraform output -raw cloudfront_distribution_id)

# Create invalidation
aws cloudfront create-invalidation \
  --distribution-id $DIST_ID \
  --paths "/*"
```

## Outputs

After applying, you can view the outputs:

```bash
terraform output
```

Key outputs:
- `website_url`: The CloudFront URL for your website
- `cloudfront_distribution_id`: For cache invalidation
- `s3_bucket_name`: Where the website files are stored
- `codepipeline_name`: The CI/CD pipeline name

## Updating

To update the infrastructure:

```bash
terraform plan   # Review changes
terraform apply  # Apply updates
```

## Destroying

To tear down the infrastructure:

```bash
terraform destroy
```

**Warning**: This will delete all website infrastructure including the S3 bucket and CloudFront distribution.

## Troubleshooting

### Certificate Validation Stuck

If ACM certificate validation is stuck:

1. Check Route53 records were created correctly
2. Ensure the Route53 zone ID is correct
3. DNS propagation can take up to 30 minutes

### CodePipeline Failing

Check the build logs:

```bash
# Get pipeline name from output
PIPELINE=$(terraform output -raw codepipeline_name)

# View latest execution
aws codepipeline get-pipeline-execution \
  --pipeline-name $PIPELINE \
  --region us-east-1
```

### Build Errors

Common issues:

- **Node version**: Ensure buildspec uses Node 20
- **Build path**: Website must be in `/website` directory
- **Dependencies**: Check `package-lock.json` is committed

## Architecture

```
GitHub (main branch)
    ↓
CodePipeline (triggered on push)
    ↓
CodeBuild (npm ci && npm run build)
    ↓
S3 Bucket (static files)
    ↓
CloudFront (CDN)
    ↓
Route53 (DNS: sls.tf → CloudFront)
```

## Cost Estimate

- **S3**: ~$0.023/GB storage + $0.09/GB transfer
- **CloudFront**: First 10TB $0.085/GB
- **Route53**: $0.50/month per hosted zone
- **CodePipeline**: First pipeline free, $1/month each additional
- **CodeBuild**: First 100 build minutes free/month, then $0.005/min
- **ACM Certificate**: Free

Estimated monthly cost: **$5-15/month** (depending on traffic)

## Security

- S3 bucket is private (no public access)
- CloudFront uses HTTPS only (TLS 1.2+)
- ACM certificate auto-renews
- CodeBuild runs in isolated environment

## Support

For issues related to:
- **This configuration**: Open issue at sls-tf/sls.tf
- **static-website-pipeline module**: Open issue at ThomasRedstone/static-website-pipeline
