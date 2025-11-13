# LocalStack Test Migration Guide

Step-by-step guide for migrating existing Terraform tests to support LocalStack.

## Table of Contents

- [Overview](#overview)
- [Migration Process](#migration-process)
- [Step-by-Step Instructions](#step-by-step-instructions)
- [Test Categories](#test-categories)
- [Common Patterns](#common-patterns)
- [Compatibility Assessment](#compatibility-assessment)
- [Examples](#examples)
- [Validation](#validation)
- [Troubleshooting](#troubleshooting)

## Overview

### What is Test Migration?

Test migration involves updating existing Terraform test files (`.tftest.hcl`) to work with both LocalStack and AWS. The goal is dual-mode testing where the same test can run against either environment.

### Why Migrate?

**Benefits:**
- **Faster feedback** - LocalStack tests run in seconds vs minutes
- **No AWS costs** - All testing is local and free
- **Offline development** - Work without internet/AWS access
- **CI/CD efficiency** - Parallel test execution without AWS rate limits
- **Consistent environments** - No drift between test runs

**Migration Effort:**
- **Parsing tests**: 5 minutes per file (trivial)
- **Resource tests**: 10-15 minutes per file (straightforward)
- **Integration tests**: 20-30 minutes per file (requires validation relaxation)

### Migration Status

Check current progress:
```bash
# View compatibility matrix
cat docs/localstack-test-matrix.md

# Count migrated tests
grep -l "LocalStack Compatibility:" tests/*.tftest.hcl | wc -l

# Count total tests
ls tests/*.tftest.hcl | wc -l
```

As of this guide:
- **16/40 tests migrated** (40%)
- **24 tests remaining** (60%)
- **Expected final compatibility**: 90-95%

## Migration Process

### High-Level Steps

1. **Assess compatibility** - Determine if test can work with LocalStack
2. **Add metadata header** - Document compatibility level
3. **Add provider configuration** - Enable endpoint overrides
4. **Test locally** - Verify with LocalStack
5. **Adjust assertions** - Relax strict AWS-specific checks if needed
6. **Document** - Note any limitations or workarounds

### Time Investment

**Per test file:**
- Assessment: 2-3 minutes
- Header + provider: 2 minutes
- Testing: 5-10 minutes
- Adjustments: 0-15 minutes (varies)
- **Total: 10-30 minutes per file**

**Entire test suite (40 files):**
- Optimistic: 6-8 hours
- Realistic: 10-12 hours
- Conservative: 15-20 hours

## Step-by-Step Instructions

### Step 1: Choose a Test File

Start with simpler tests first:

**Easy (Start Here):**
- Parsing tests (no AWS resources)
- Validation tests (locals only)
- S3 tests (excellent LocalStack support)

**Medium:**
- SNS/SQS tests (good support)
- API Gateway tests (good support)
- DynamoDB tests (good support)

**Hard (Save for Later):**
- Custom domain tests (Route 53 ACM limitations)
- IAM policy tests (less strict validation)
- Lambda deployment tests (layer support varies)

### Step 2: Assess Compatibility

Review the test and determine compatibility level:

**FULL Compatibility:**
- No AWS resources created (parsing only)
- Only well-supported services (S3, SNS, SQS)
- No strict AWS-specific assertions

**PARTIAL Compatibility:**
- Uses services with limitations
- Requires relaxed assertions
- Some features unavailable

**NONE Compatibility:**
- Requires unsupported services
- Tests AWS-specific behavior LocalStack doesn't emulate
- Would require significant test restructuring

Example assessment:
```hcl
# tests/custom_domain.tftest.hcl
# Uses Route 53 + ACM - limited LocalStack support
# Verdict: PARTIAL or NONE
```

### Step 3: Add Compatibility Header

Add metadata at the top of the file:

```hcl
# Test Name
# LocalStack Compatibility: FULL
# Description of what this test validates
```

**Header Template:**
```hcl
# [Original Test Name]
# LocalStack Compatibility: [FULL|PARTIAL|NONE]
# [Brief description of test purpose]
# [Optional: Note about limitations or required setup]
```

**Examples:**

For parsing test:
```hcl
# HTTP Event Parsing Tests
# LocalStack Compatibility: FULL
# Tests for extracting and parsing HTTP events from Serverless Framework configuration
# These are parsing tests that validate locals - no AWS resources are created
```

For resource test:
```hcl
# S3 Bucket Management Tests
# LocalStack Compatibility: FULL
# Tests S3 bucket creation, configuration, and event notification setup
# All S3 operations are well-supported in LocalStack
```

For limited test:
```hcl
# Custom Domain Configuration Tests
# LocalStack Compatibility: PARTIAL
# Tests custom domain setup with ACM certificates and Route 53
# Note: ACM certificate validation and Route 53 hosted zones have limited support
```

### Step 4: Add Provider Configuration

Add the provider block after the header, before the first `run` block:

**Copy from template:**
```bash
cat tests/test_provider_template.txt
```

**Or copy this:**
```hcl
provider "aws" {
  region = "us-east-1"

  # Skip credential validation when using LocalStack
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack

  # S3 path-style access required for LocalStack
  s3_use_path_style = var.use_localstack

  # Dynamic endpoint configuration for LocalStack
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

**Placement:**
```hcl
# Test Name
# LocalStack Compatibility: FULL

provider "aws" {
  # ... provider configuration
}

variables {
  # ... existing variables if any
}

run "first_test" {
  # ... test code
}
```

### Step 5: Test Locally

Run the test with LocalStack:

```bash
# Start LocalStack if not running
make localstack-start

# Run the specific test
terraform test -filter="tests/your_test.tftest.hcl" -var="use_localstack=true"

# Watch for errors or failures
```

### Step 6: Adjust Assertions (If Needed)

If tests fail, determine if assertions need relaxation:

**Common Adjustments:**

**URL Format Differences:**
```hcl
# Before (AWS-specific)
assert {
  condition = can(regex("execute-api\\.us-east-1\\.amazonaws\\.com",
    aws_api_gateway_deployment.api.invoke_url))
  error_message = "Invalid API Gateway URL format"
}

# After (dual-mode)
assert {
  condition = var.use_localstack ? (
    can(regex("localhost:4566", aws_api_gateway_deployment.api.invoke_url))
  ) : (
    can(regex("execute-api\\.us-east-1\\.amazonaws\\.com",
      aws_api_gateway_deployment.api.invoke_url))
  )
  error_message = "Invalid API Gateway URL format"
}
```

**ARN Format Differences:**
```hcl
# Before
assert {
  condition = can(regex("^arn:aws:", aws_lambda_function.fn.arn))
  error_message = "Invalid Lambda ARN"
}

# After
assert {
  condition = can(regex("^arn:(aws|localstack):", aws_lambda_function.fn.arn))
  error_message = "Invalid Lambda ARN"
}
```

**Account ID Validation:**
```hcl
# Before
assert {
  condition = length(regexall("^[0-9]{12}$",
    split(":", aws_lambda_function.fn.arn)[4])) > 0
  error_message = "Invalid AWS account ID in ARN"
}

# After (skip in LocalStack)
assert {
  condition = var.use_localstack || length(regexall("^[0-9]{12}$",
    split(":", aws_lambda_function.fn.arn)[4])) > 0
  error_message = "Invalid AWS account ID in ARN"
}
```

**Certificate Validation:**
```hcl
# Before
assert {
  condition = aws_acm_certificate.cert.status == "ISSUED"
  error_message = "Certificate must be issued"
}

# After
assert {
  condition = var.use_localstack ? true : (
    aws_acm_certificate.cert.status == "ISSUED"
  )
  error_message = "Certificate must be issued"
}
```

### Step 7: Document Changes

If you made assertion adjustments, document them:

**In test header:**
```hcl
# Custom Domain Configuration Tests
# LocalStack Compatibility: PARTIAL
# Tests custom domain setup with ACM certificates
# Note: Certificate validation assertions relaxed for LocalStack
```

**In assertion comments:**
```hcl
assert {
  # Relaxed for LocalStack - certificate validation not fully supported
  condition = var.use_localstack ? true : (
    aws_acm_certificate.cert.status == "ISSUED"
  )
  error_message = "Certificate must be issued"
}
```

### Step 8: Update Compatibility Matrix

Add your test to the matrix:

```bash
# Edit the matrix
vim docs/localstack-test-matrix.md

# Add line under appropriate section:
# - tests/your_test.tftest.hcl - FULL - [description]
```

## Test Categories

### Category 1: Parsing Tests (Easiest)

**Characteristics:**
- No AWS resources created
- Only validate `locals` values
- Test YAML parsing and transformation logic

**Migration effort:** 5 minutes
**Expected compatibility:** FULL (100%)

**Examples:**
- `tests/http_event_parsing.tftest.hcl`
- `tests/s3_event_parsing.tftest.hcl`
- `tests/event_source_parsing.tftest.hcl`

**Migration steps:**
1. Add header
2. Add provider block
3. Test (should pass immediately)

### Category 2: Validation Tests (Easy)

**Characteristics:**
- Test input validation
- Expect errors or specific conditions
- May create resources but focus on validation

**Migration effort:** 10 minutes
**Expected compatibility:** FULL (95%)

**Examples:**
- `tests/s3_validation.tftest.hcl`
- `tests/event_source_validation.tftest.hcl`

**Migration steps:**
1. Add header and provider
2. Test with LocalStack
3. Verify error messages are consistent

### Category 3: Resource Creation Tests (Medium)

**Characteristics:**
- Create AWS resources
- Validate resource attributes
- Test resource relationships

**Migration effort:** 15-20 minutes
**Expected compatibility:** FULL to PARTIAL (80-90%)

**Examples:**
- `tests/s3_bucket_management.tftest.hcl`
- `tests/api_gateway_resources.tftest.hcl`
- `tests/sns_resources.tftest.hcl`

**Migration steps:**
1. Add header and provider
2. Test with LocalStack
3. Adjust URL/ARN format assertions if needed
4. Verify resource attributes match expectations

### Category 4: Integration Tests (Hard)

**Characteristics:**
- Test multiple services together
- Complex assertions on resource state
- May involve triggers or events

**Migration effort:** 20-30 minutes
**Expected compatibility:** PARTIAL (60-80%)

**Examples:**
- `tests/custom_domain.tftest.hcl`
- `tests/lambda_layers.tftest.hcl`
- Complex event source mappings

**Migration steps:**
1. Add header and provider
2. Test with LocalStack
3. Identify failing assertions
4. Determine which assertions can be relaxed
5. Add conditional logic for LocalStack
6. Document limitations

### Category 5: AWS-Specific Tests (Hardest)

**Characteristics:**
- Test AWS-specific behavior
- Require features LocalStack doesn't support
- May need significant restructuring

**Migration effort:** 30+ minutes or skip
**Expected compatibility:** PARTIAL to NONE (0-50%)

**Examples:**
- IAM policy validation tests
- X-Ray tracing tests
- CloudFormation stack tests

**Decision:** Mark as NONE and skip, or create separate LocalStack-specific tests

## Common Patterns

### Pattern 1: Conditional Assertions

```hcl
assert {
  condition = var.use_localstack ? (
    # LocalStack condition
    can(regex("localhost:4566", resource.endpoint))
  ) : (
    # AWS condition
    can(regex("amazonaws\\.com", resource.endpoint))
  )
  error_message = "Invalid endpoint"
}
```

### Pattern 2: Skip AWS-Specific Checks

```hcl
assert {
  condition = var.use_localstack || (
    # AWS-only validation
    resource.property == "expected_value"
  )
  error_message = "Property validation failed"
}
```

### Pattern 3: Relaxed ARN Validation

```hcl
assert {
  condition = can(regex("^arn:(aws|localstack):", resource.arn))
  error_message = "Invalid ARN format"
}
```

### Pattern 4: Optional Certificate Validation

```hcl
assert {
  condition = var.use_localstack ? (
    resource.certificate_arn != null
  ) : (
    resource.certificate_arn != null &&
    resource.certificate_status == "ISSUED"
  )
  error_message = "Certificate validation failed"
}
```

### Pattern 5: Account ID Flexibility

```hcl
locals {
  # Extract account ID, allowing LocalStack's format
  account_id = split(":", resource.arn)[4]
  valid_account = var.use_localstack ? (
    length(local.account_id) > 0
  ) : (
    can(regex("^[0-9]{12}$", local.account_id))
  )
}

assert {
  condition = local.valid_account
  error_message = "Invalid account ID"
}
```

## Compatibility Assessment

### Quick Assessment Checklist

For each test file, check:

- [ ] What AWS services are used?
- [ ] Are resources created or just locals validated?
- [ ] Are there strict format assertions (URLs, ARNs)?
- [ ] Are there certificate or domain validations?
- [ ] Are there IAM policy validations?
- [ ] Are there timing-dependent checks?

### Decision Tree

```
Does test create AWS resources?
├─ NO → FULL compatibility (parsing test)
│
└─ YES → What services?
   ├─ S3, SNS, SQS, API Gateway, Lambda → Likely FULL
   ├─ DynamoDB, EventBridge → Likely FULL
   ├─ Route 53, ACM → Likely PARTIAL
   ├─ IAM (policy validation) → Likely PARTIAL
   └─ X-Ray, CloudWatch Logs → Likely NONE

   Are there strict AWS format checks?
   ├─ URL formats → Need conditional assertions → FULL
   ├─ ARN formats → Need regex adjustment → FULL
   ├─ Account IDs → Need relaxation → FULL
   └─ Certificate validation → Need conditional → PARTIAL
```

### Service Support Matrix

| Service | LocalStack Support | Migration Effort | Expected Compatibility |
|---------|-------------------|------------------|------------------------|
| Lambda | Excellent | Low | FULL |
| API Gateway | Excellent | Low | FULL |
| S3 | Excellent | Low | FULL |
| SNS | Excellent | Low | FULL |
| SQS | Excellent | Low | FULL |
| DynamoDB | Excellent | Low | FULL |
| EventBridge | Good | Medium | FULL |
| IAM | Good | Medium | PARTIAL |
| Route 53 | Limited | High | PARTIAL |
| ACM | Limited | High | PARTIAL |
| CloudWatch Logs | Good | Low | FULL |
| X-Ray | None | N/A | NONE |

## Examples

### Example 1: Simple Parsing Test

**Before:**
```hcl
# HTTP Event Parsing Tests

run "short_form_http_event" {
  command = plan

  assert {
    condition = local.http_events["hello"].method == "GET"
    error_message = "Expected GET method"
  }
}
```

**After:**
```hcl
# HTTP Event Parsing Tests
# LocalStack Compatibility: FULL
# Tests for extracting and parsing HTTP events from Serverless Framework configuration
# These are parsing tests that validate locals - no AWS resources are created

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

run "short_form_http_event" {
  command = plan

  assert {
    condition = local.http_events["hello"].method == "GET"
    error_message = "Expected GET method"
  }
}
```

**Changes:** Added header + provider block. No assertion changes needed.

### Example 2: Resource Test with URL Validation

**Before:**
```hcl
# API Gateway Deployment Tests

run "api_gateway_deployment" {
  command = apply

  assert {
    condition = can(regex("execute-api\\.us-east-1\\.amazonaws\\.com",
      aws_api_gateway_deployment.api.invoke_url))
    error_message = "Invalid invoke URL"
  }
}
```

**After:**
```hcl
# API Gateway Deployment Tests
# LocalStack Compatibility: FULL
# Tests API Gateway deployment and stage creation

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

run "api_gateway_deployment" {
  command = apply

  assert {
    # URL format differs between LocalStack and AWS
    condition = var.use_localstack ? (
      can(regex("localhost:4566", aws_api_gateway_deployment.api.invoke_url))
    ) : (
      can(regex("execute-api\\.us-east-1\\.amazonaws\\.com",
        aws_api_gateway_deployment.api.invoke_url))
    )
    error_message = "Invalid invoke URL"
  }
}
```

**Changes:** Added conditional assertion for URL format.

### Example 3: Certificate Validation

**Before:**
```hcl
# Custom Domain Tests

run "certificate_validation" {
  command = apply

  assert {
    condition = aws_acm_certificate.cert.status == "ISSUED"
    error_message = "Certificate must be issued"
  }

  assert {
    condition = can(regex("^[0-9]{12}$",
      split(":", aws_acm_certificate.cert.arn)[4]))
    error_message = "Invalid account ID"
  }
}
```

**After:**
```hcl
# Custom Domain Tests
# LocalStack Compatibility: PARTIAL
# Tests custom domain configuration with ACM certificates
# Note: Certificate validation is skipped in LocalStack as the validation
# workflow is not fully supported

provider "aws" {
  region = "us-east-1"
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack
  s3_use_path_style = var.use_localstack

  dynamic "endpoints" {
    for_each = var.use_localstack ? [1] : []
    content {
      acm        = var.localstack_endpoint
      apigateway = var.localstack_endpoint
      route53    = var.localstack_endpoint
      lambda     = var.localstack_endpoint
      iam        = var.localstack_endpoint
      sts        = var.localstack_endpoint
    }
  }
}

run "certificate_validation" {
  command = apply

  assert {
    # LocalStack creates certificates but doesn't validate them
    condition = var.use_localstack ? (
      aws_acm_certificate.cert.arn != null
    ) : (
      aws_acm_certificate.cert.status == "ISSUED"
    )
    error_message = "Certificate must be issued"
  }

  assert {
    # LocalStack uses different account ID format
    condition = var.use_localstack || (
      can(regex("^[0-9]{12}$",
        split(":", aws_acm_certificate.cert.arn)[4]))
    )
    error_message = "Invalid account ID"
  }
}
```

**Changes:** Relaxed certificate status check and account ID validation for LocalStack.

## Validation

### Pre-Migration Validation

Before migrating, ensure tests work with AWS:

```bash
# Run test against AWS
terraform test -filter="tests/your_test.tftest.hcl" -var="use_localstack=false"

# Should pass
```

### Post-Migration Validation

After migration, validate with both environments:

```bash
# Test with LocalStack
make localstack-start
terraform test -filter="tests/your_test.tftest.hcl" -var="use_localstack=true"

# Test with AWS (if credentials available)
terraform test -filter="tests/your_test.tftest.hcl" -var="use_localstack=false"

# Both should pass
```

### Checklist

- [ ] Test header includes compatibility level
- [ ] Provider configuration added
- [ ] Test passes with LocalStack
- [ ] Test still passes with AWS (if possible to verify)
- [ ] Assertions are appropriately conditional
- [ ] Changes are documented in test comments
- [ ] Compatibility matrix updated

## Troubleshooting

### Test Times Out with LocalStack

**Cause:** Resource creation is slow or stuck

**Solution:**
```bash
# Check LocalStack logs
make localstack-logs

# Look for errors or warnings
# Common issue: Service not loaded

# Verify service is enabled in docker-compose.localstack.yml
```

### S3 Operations Fail

**Cause:** Path-style access not enabled

**Solution:**
```hcl
provider "aws" {
  s3_use_path_style = var.use_localstack  # Must be true for LocalStack
}
```

### ARN Format Errors

**Cause:** LocalStack uses `arn:localstack:` prefix

**Solution:**
```hcl
# Change from:
can(regex("^arn:aws:", resource.arn))

# To:
can(regex("^arn:(aws|localstack):", resource.arn))
```

### Account ID Validation Fails

**Cause:** LocalStack uses `000000000000` instead of real account ID

**Solution:**
```hcl
# Skip validation in LocalStack
condition = var.use_localstack || can(regex("^[0-9]{12}$", account_id))
```

### Certificate Not Issued

**Cause:** LocalStack doesn't perform certificate validation workflow

**Solution:**
```hcl
# Accept certificate existence in LocalStack
condition = var.use_localstack ? (
  aws_acm_certificate.cert.arn != null
) : (
  aws_acm_certificate.cert.status == "ISSUED"
)
```

### URL Format Doesn't Match

**Cause:** LocalStack uses `localhost:4566` instead of AWS URLs

**Solution:**
```hcl
condition = var.use_localstack ? (
  can(regex("localhost:4566", url))
) : (
  can(regex("amazonaws\\.com", url))
)
```

## Next Steps

1. **Start with parsing tests** - Easy wins to build confidence
2. **Move to resource tests** - S3, SNS, SQS have excellent support
3. **Tackle integration tests** - Require more assertion adjustments
4. **Document limitations** - Note any tests that can't be migrated

## References

- [LocalStack Testing Guide](./localstack-testing.md)
- [Test Compatibility Matrix](./localstack-test-matrix.md)
- [Provider Configuration Guide](./localstack-provider-config.md)
- [LocalStack Service Coverage](https://docs.localstack.cloud/user-guide/aws/feature-coverage/)
