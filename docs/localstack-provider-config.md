# LocalStack Provider Configuration

This document explains how to configure the AWS provider for LocalStack testing.

## Important: Provider Configuration Pattern

This Terraform module **does NOT declare the AWS provider**. This follows Terraform module best practices, allowing tests to configure the provider with endpoint overrides for LocalStack.

## Test Provider Configuration

Tests must provide their own AWS provider configuration. When testing with LocalStack, the provider configuration must include:

### Required Provider Settings

```hcl
provider "aws" {
  region = "us-east-1"

  # Skip AWS-specific validations when using LocalStack
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack

  # CRITICAL: S3 requires path-style access in LocalStack
  s3_use_path_style = var.use_localstack

  # Dynamic endpoints block - only populated when use_localstack = true
  dynamic "endpoints" {
    for_each = var.use_localstack ? [1] : []
    content {
      apigateway = var.localstack_endpoint
      dynamodb   = var.localstack_endpoint
      events     = var.localstack_endpoint
      iam        = var.localstack_endpoint
      lambda     = var.localstack_endpoint
      route53    = var.localstack_endpoint
      s3         = var.localstack_endpoint
      sns        = var.localstack_endpoint
      sqs        = var.localstack_endpoint
      sts        = var.localstack_endpoint
    }
  }
}
```

### Service Endpoints

The module uses the following AWS services:
- **apigateway**: API Gateway REST API resources
- **dynamodb**: DynamoDB tables and streams
- **events**: CloudWatch Events (EventBridge)
- **iam**: IAM roles and policies
- **lambda**: Lambda functions and permissions
- **route53**: Route 53 hosted zones and records
- **s3**: S3 buckets and notifications
- **sns**: SNS topics
- **sqs**: SQS queues
- **sts**: AWS STS for identity

All endpoints point to the LocalStack gateway (`http://localhost:4566`) when `use_localstack = true`.

## Usage in Tests

### Example Test File

```hcl
# test_example.tftest.hcl
# LocalStack Compatibility: FULL

provider "aws" {
  region = "us-east-1"
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack
  s3_use_path_style = var.use_localstack

  dynamic "endpoints" {
    for_each = var.use_localstack ? [1] : []
    content {
      apigateway = var.localstack_endpoint
      dynamodb   = var.localstack_endpoint
      events     = var.localstack_endpoint
      iam        = var.localstack_endpoint
      lambda     = var.localstack_endpoint
      route53    = var.localstack_endpoint
      s3         = var.localstack_endpoint
      sns        = var.localstack_endpoint
      sqs        = var.localstack_endpoint
      sts        = var.localstack_endpoint
    }
  }
}

run "test_with_localstack" {
  command = plan

  variables {
    config_path = "tests/fixtures/example.yml"
  }

  assert {
    condition     = length(aws_lambda_function.functions) > 0
    error_message = "Lambda functions should be created"
  }
}
```

### Running Tests

```bash
# With LocalStack (default via use_localstack variable default)
terraform test -var="use_localstack=true"

# Or use Make target
make test-local

# With real AWS
terraform test -var="use_localstack=false"

# Or use Make target
make test-aws
```

## Critical Configuration Notes

### S3 Path-Style Access

LocalStack requires S3 path-style access (`s3.amazonaws.com/bucket/key` instead of `bucket.s3.amazonaws.com/key`). This is configured via:

```hcl
s3_use_path_style = var.use_localstack
```

**Forgetting this setting will cause S3 operations to fail in LocalStack.**

### Skip Validations

LocalStack doesn't support AWS credential validation, metadata API, or account ID lookups. These must be skipped:

```hcl
skip_credentials_validation = var.use_localstack
skip_metadata_api_check     = var.use_localstack
skip_requesting_account_id  = var.use_localstack
```

### Dynamic Endpoints

The `dynamic "endpoints"` block only populates when `use_localstack = true`. This ensures:
- LocalStack mode: All services point to `http://localhost:4566`
- AWS mode: Services use default AWS endpoints

## Testing Both Modes

To ensure tests work with both LocalStack and AWS:

1. Write tests that don't depend on AWS-specific behavior
2. Use conditional assertions for behavior differences
3. Mark LocalStack compatibility in test file headers
4. Test locally with LocalStack, validate periodically with AWS

Example conditional assertion:

```hcl
assert {
  condition = var.use_localstack || can(regex("execute-api", output.invoke_url))
  error_message = "AWS invoke URL should contain execute-api (skipped in LocalStack)"
}
```

## References

- [LocalStack Documentation](https://docs.localstack.cloud/)
- [Terraform AWS Provider Configuration](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#configuration-reference)
- [LocalStack AWS Service Coverage](https://docs.localstack.cloud/user-guide/aws/feature-coverage/)
