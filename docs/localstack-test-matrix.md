# LocalStack Test Compatibility Matrix

This document provides a comprehensive overview of test file compatibility with LocalStack Community Edition.

## Summary Statistics

**Converted Tests:** 16 out of ~40 test files (40%)
**FULL Compatibility:** 16 files
**PARTIAL Compatibility:** 0 files (to be determined for remaining files)
**NONE Compatibility:** 0 files (to be determined for remaining files)

## Test File Status

### ✅ Converted to Dual-Mode (LocalStack + AWS)

| Test File | Compatibility | Type | Notes |
|-----------|---------------|------|-------|
| `http_event_parsing.tftest.hcl` | FULL | Parsing | HTTP event extraction and parsing logic |
| `s3_event_parsing.tftest.hcl` | FULL | Parsing | S3 event syntax parsing |
| `path_parsing.tftest.hcl` | FULL | Parsing | API Gateway path parsing |
| `event_source_parsing.tftest.hcl` | FULL | Parsing | DynamoDB/SQS event detection |
| `s3_validation.tftest.hcl` | FULL | Validation | S3 configuration validation |
| `api_gateway_resources.tftest.hcl` | FULL | Resources | API Gateway REST API creation |
| `api_gateway_integration.tftest.hcl` | FULL | Resources | Lambda integration setup |
| `api_gateway_deployment.tftest.hcl` | FULL | Resources | Deployment and stage creation |
| `cors_configuration.tftest.hcl` | FULL | Resources | CORS header configuration |
| `s3_bucket_management.tftest.hcl` | FULL | Resources | S3 bucket creation and notifications |
| `defaults.tftest.hcl` | FULL | Parsing | Default value application |
| `sns_parsing.tftest.hcl` | FULL | Parsing | SNS topic parsing |
| `sns_resources.tftest.hcl` | FULL | Resources | SNS topic resource creation |
| `sqs_parsing.tftest.hcl` | FULL | Parsing | SQS queue parsing |
| `sqs_resources.tftest.hcl` | FULL | Resources | SQS queue resource creation |
| `shared_test_config.tftest.hcl` | TEMPLATE | Template | Reusable provider configuration |

### 📋 Pending Conversion (Need Provider Configuration)

| Test File | Expected Compatibility | Type | Notes |
|-----------|------------------------|------|-------|
| `code_packaging.tftest.hcl` | FULL | Resources | Lambda code packaging |
| `custom_domain.tftest.hcl` | FULL | Resources | Custom domain configuration |
| `custom_resources_parsing.tftest.hcl` | FULL | Parsing | Custom resource parsing |
| `custom_resources_translation.tftest.hcl` | FULL | Resources | CloudFormation to Terraform translation |
| `event_source_validation.tftest.hcl` | FULL | Validation | Event source validation logic |
| `eventbridge_parsing.tftest.hcl` | FULL | Parsing | EventBridge rule parsing |
| `eventbridge_resources.tftest.hcl` | FULL | Resources | EventBridge rule creation |
| `iam_policy_merging.tftest.hcl` | FULL | Parsing | IAM policy merging logic |
| `iam_policy_resources.tftest.hcl` | FULL | Resources | IAM policy resource creation |
| `iam_roles.tftest.hcl` | FULL | Resources | IAM role creation |
| `iam_statement_parsing.tftest.hcl` | FULL | Parsing | IAM statement parsing |
| `iam_validation.tftest.hcl` | FULL | Validation | IAM validation logic |
| `lambda_outputs.tftest.hcl` | FULL | Outputs | Lambda output values |
| `lambda_resources.tftest.hcl` | FULL | Resources | Lambda function creation |
| `provider_setup.tftest.hcl` | FULL | Setup | Provider configuration |
| `validation.tftest.hcl` | FULL | Validation | General validation logic |
| `yaml_parsing.tftest.hcl` | FULL | Parsing | YAML parsing logic |
| `gap_coverage.tftest.hcl` | PARTIAL | E2E | End-to-end coverage - may have AWS-specific checks |

## LocalStack Service Support

### Fully Supported Services (Community Edition)

| AWS Service | LocalStack Support | Test Files Using Service |
|-------------|-------------------|--------------------------|
| Lambda | ✅ Full | lambda_resources, api_gateway_integration |
| API Gateway | ✅ Full | api_gateway_*, cors_configuration |
| S3 | ✅ Full | s3_* |
| IAM | ⚠️ Partial | iam_* (less strict validation) |
| DynamoDB | ✅ Full | event_source_*, custom_resources_* |
| SQS | ✅ Full | sqs_*, event_source_* |
| SNS | ✅ Full | sns_* |
| EventBridge | ✅ Full | eventbridge_* |
| CloudWatch Events | ✅ Full | eventbridge_* |

### Known Limitations

#### IAM
- **LocalStack Behavior:** Less strict IAM policy validation
- **Impact:** Some IAM validation tests may pass in LocalStack but fail in AWS
- **Workaround:** Use conditional assertions: `var.use_localstack || strict_validation`
- **Affected Tests:** iam_validation.tftest.hcl, iam_policy_resources.tftest.hcl

#### API Gateway
- **LocalStack Behavior:** Different invoke URL format
  - LocalStack: `http://localhost:4566/restapis/{id}/{stage}/_user_request/{path}`
  - AWS: `https://{api-id}.execute-api.{region}.amazonaws.com/{stage}/{path}`
- **Impact:** URL format validation needs conditional logic
- **Workaround:** Check for different URL patterns based on `var.use_localstack`
- **Affected Tests:** api_gateway_deployment.tftest.hcl (output tests)

#### Lambda
- **LocalStack Behavior:** Lambda execution uses Docker containers locally
- **Impact:** Function invocation may have different timing
- **Workaround:** Not applicable for plan-only tests
- **Affected Tests:** None (we only test plan, not apply/invoke)

#### Route 53
- **LocalStack Behavior:** Basic DNS functionality, advanced routing not supported
- **Impact:** Complex routing policies may not work
- **Workaround:** Mark complex tests as PARTIAL or AWS-only
- **Affected Tests:** custom_domain.tftest.hcl (basic operations should work)

## Conversion Guidelines

### For FULL Compatibility Tests

1. Add LocalStack compatibility header:
   ```hcl
   # Test Name
   # LocalStack Compatibility: FULL
   # Description
   ```

2. Add provider configuration block (copy from `tests/test_provider_template.txt`)

3. Test should work identically in both modes with no conditional logic

### For PARTIAL Compatibility Tests

1. Add LocalStack compatibility header:
   ```hcl
   # Test Name
   # LocalStack Compatibility: PARTIAL
   # Description - some features require AWS
   ```

2. Add provider configuration block

3. Use conditional assertions for AWS-specific behavior:
   ```hcl
   assert {
     condition = var.use_localstack || strict_aws_check
     error_message = "AWS-specific validation (relaxed in LocalStack)"
   }
   ```

### For NONE Compatibility Tests

1. Add LocalStack compatibility header:
   ```hcl
   # Test Name
   # LocalStack Compatibility: NONE
   # Description - requires AWS Pro or unsupported features
   ```

2. Still add provider configuration (for consistency)

3. Document why test requires AWS

## Running Tests

### With LocalStack

```bash
# Start LocalStack
make localstack-start

# Run all tests
make test-local

# Run specific test file
terraform test -filter="tests/http_event_parsing.tftest.hcl" -var="use_localstack=true"
```

### With AWS

```bash
# Run all tests
make test-aws

# Run specific test file
terraform test -filter="tests/http_event_parsing.tftest.hcl" -var="use_localstack=false"
```

## Expected Test Results

### Phase 1: Core Parsing Tests (5 files)
- ✅ **100% pass rate** expected with LocalStack
- These tests only validate Terraform locals, no AWS API calls

### Phase 2: Resource Creation Tests (5 files)
- ✅ **100% pass rate** expected with LocalStack
- LocalStack supports API Gateway and S3 fully

### Phase 3: Remaining Tests (~20 files)
- ✅ **~90-95% pass rate** expected with LocalStack
- Most tests are parsing or basic resource creation
- IAM tests may need conditional assertions for strict validation
- Advanced features (permission boundaries) may need AWS-only markers

## Troubleshooting Common Issues

### Issue: S3 Bucket Operations Fail

**Symptom:** S3 bucket creation or notification errors

**Solution:** Ensure `s3_use_path_style = var.use_localstack` in provider config

**Files Affected:** s3_bucket_management.tftest.hcl, s3_event_parsing.tftest.hcl

### Issue: IAM Validation Too Strict

**Symptom:** IAM policy or role validation fails in LocalStack

**Solution:** Use conditional assertion:
```hcl
assert {
  condition = var.use_localstack || can(regex("^arn:aws:iam::", role.arn))
  error_message = "IAM ARN format (relaxed in LocalStack)"
}
```

**Files Affected:** iam_*.tftest.hcl

### Issue: API Gateway URL Format Mismatch

**Symptom:** Invoke URL format validation fails

**Solution:** Check for appropriate URL pattern:
```hcl
assert {
  condition = (
    var.use_localstack && can(regex("localhost", url)) ||
    !var.use_localstack && can(regex("execute-api", url))
  )
  error_message = "URL format differs between LocalStack and AWS"
}
```

**Files Affected:** api_gateway_deployment.tftest.hcl

## Next Steps

1. **Convert Remaining Tests:** Add provider configuration to ~20 remaining test files
2. **Run Full Suite:** Execute complete test suite with LocalStack
3. **Document Failures:** Update matrix with any unexpected failures
4. **Add Conditional Logic:** For tests that need different behavior in LocalStack vs AWS
5. **CI/CD Integration:** Add GitHub Actions workflow for automated LocalStack testing

## References

- [LocalStack Testing Guide](./localstack-testing.md)
- [Provider Configuration Guide](./localstack-provider-config.md)
- [LocalStack Service Coverage](https://docs.localstack.cloud/user-guide/aws/feature-coverage/)
- [Test Provider Template](../tests/test_provider_template.txt)
