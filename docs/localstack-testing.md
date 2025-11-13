# LocalStack Testing Guide

This guide explains how to write and run tests that work with both LocalStack and real AWS.

## Table of Contents

1. [Compatibility Metadata Standard](#compatibility-metadata-standard)
2. [Test Skip Patterns](#test-skip-patterns)
3. [Graceful Degradation Patterns](#graceful-degradation-patterns)
4. [Test Writing Checklist](#test-writing-checklist)
5. [Common Scenarios](#common-scenarios)
6. [Troubleshooting](#troubleshooting)

## Compatibility Metadata Standard

Every test file should include a compatibility header at the top:

```hcl
# <Test File Name>
# LocalStack Compatibility: <FULL|PARTIAL|NONE>
# <Description>
```

### Compatibility Levels

**FULL** - All tests work with LocalStack Community Edition
- Tests use supported AWS services
- No advanced IAM features required
- No AWS-specific behavior dependencies
- Example: Parsing tests, basic resource creation

```hcl
# HTTP Event Parsing Tests
# LocalStack Compatibility: FULL
# Tests parsing of HTTP events from serverless.yml - no AWS resources created
```

**PARTIAL** - Some tests require real AWS
- Most tests work with LocalStack
- Some tests need AWS-only features (marked with skip conditions)
- Example: Tests with advanced EventBridge patterns

```hcl
# EventBridge Integration Tests
# LocalStack Compatibility: PARTIAL
# Basic event rules work in LocalStack, complex patterns require AWS
```

**NONE** - Test file requires real AWS
- Uses LocalStack Pro features (not in Community Edition)
- Requires advanced IAM permission boundaries
- Uses AWS-specific validation
- Example: Complex Route 53 routing policies

```hcl
# Advanced Route 53 Routing Tests
# LocalStack Compatibility: NONE
# Requires advanced routing policies not supported in LocalStack Community
```

## Test Skip Patterns

### Pattern 1: Conditional Assertions

Use conditional logic to skip AWS-specific validations when running in LocalStack:

```hcl
run "iam_role_validation" {
  command = plan

  variables {
    config_path = "tests/fixtures/lambda-basic.yml"
  }

  # Strict validation for AWS, relaxed for LocalStack
  assert {
    condition = var.use_localstack || can(regex("^arn:aws:iam::", aws_iam_role.lambda.arn))
    error_message = "IAM role ARN should be valid AWS format (relaxed in LocalStack)"
  }
}
```

### Pattern 2: Mode-Specific Assertions

Create separate assertions for LocalStack and AWS modes:

```hcl
run "api_gateway_url_format" {
  command = plan

  variables {
    config_path = "tests/fixtures/api-gateway.yml"
  }

  # LocalStack URL format check
  assert {
    condition = !var.use_localstack || can(regex("localhost:4566", aws_api_gateway_deployment.main.invoke_url))
    error_message = "LocalStack invoke URL should contain localhost:4566"
  }

  # AWS URL format check
  assert {
    condition = var.use_localstack || can(regex("execute-api.*amazonaws.com", aws_api_gateway_deployment.main.invoke_url))
    error_message = "AWS invoke URL should contain execute-api.amazonaws.com"
  }
}
```

### Pattern 3: Skip Complex Features

For features not supported in LocalStack Community Edition, document and skip:

```hcl
run "iam_permission_boundary" {
  command = plan

  variables {
    config_path = "tests/fixtures/iam-boundary.yml"
  }

  # This feature requires real AWS
  # LocalStack Community Edition doesn't validate permission boundaries
  assert {
    condition = var.use_localstack || aws_iam_role.lambda.permissions_boundary != null
    error_message = "Permission boundary should be set (AWS only - skipped in LocalStack)"
  }
}
```

## Graceful Degradation Patterns

### Pattern 1: Relaxed ARN Validation

LocalStack ARNs may have different formats:

```hcl
# Strict AWS validation
assert {
  condition = var.use_localstack || can(regex("^arn:aws:[a-z0-9-]+:[a-z0-9-]*:[0-9]{12}:", resource.arn))
  error_message = "ARN format validation (relaxed in LocalStack)"
}

# Check ARN exists (both modes)
assert {
  condition     = resource.arn != null && resource.arn != ""
  error_message = "Resource ARN must be non-empty"
}
```

### Pattern 2: IAM Policy Validation Differences

LocalStack has less strict IAM validation:

```hcl
run "iam_policy_validation" {
  command = plan

  variables {
    config_path = "tests/fixtures/iam-policy.yml"
  }

  # Core logic validation (works in both modes)
  assert {
    condition     = length(jsondecode(aws_iam_role_policy.custom.policy).Statement) > 0
    error_message = "Policy should have at least one statement"
  }

  # AWS-specific validation (skipped in LocalStack)
  assert {
    condition = var.use_localstack || can(jsondecode(aws_iam_role_policy.custom.policy))
    error_message = "Policy should be valid JSON (strict validation in AWS only)"
  }
}
```

### Pattern 3: API Gateway Invoke URL Format

LocalStack and AWS have different URL formats:

```hcl
run "api_invoke_url" {
  command = plan

  variables {
    config_path = "tests/fixtures/api-gateway.yml"
  }

  # URL exists (both modes)
  assert {
    condition     = aws_api_gateway_deployment.main.invoke_url != null
    error_message = "Invoke URL should be generated"
  }

  # Format check with graceful degradation
  assert {
    condition = (
      var.use_localstack && can(regex("localhost", aws_api_gateway_deployment.main.invoke_url)) ||
      !var.use_localstack && can(regex("execute-api", aws_api_gateway_deployment.main.invoke_url))
    )
    error_message = "Invoke URL should have correct format for mode (LocalStack: localhost, AWS: execute-api)"
  }
}
```

### Pattern 4: EventBridge Pattern Validation

Complex EventBridge patterns may not work in LocalStack:

```hcl
run "eventbridge_pattern" {
  command = plan

  variables {
    config_path = "tests/fixtures/eventbridge-pattern.yml"
  }

  # Basic pattern parsing (both modes)
  assert {
    condition     = can(jsondecode(aws_cloudwatch_event_rule.custom.event_pattern))
    error_message = "Event pattern should be valid JSON"
  }

  # Complex pattern validation (AWS only)
  assert {
    condition = var.use_localstack || can(regex("\\$or", aws_cloudwatch_event_rule.custom.event_pattern))
    error_message = "Complex pattern operators work in AWS (may not work in LocalStack)"
  }
}
```

## Test Writing Checklist

Use this checklist when writing or converting tests for dual-mode support:

### Setup
- [ ] Add compatibility header to test file (FULL/PARTIAL/NONE)
- [ ] Copy provider configuration from template
- [ ] Verify all required AWS service endpoints included

### Test Logic
- [ ] Tests focus on module logic, not AWS API behavior
- [ ] Parsing tests work identically (no AWS resources created)
- [ ] Resource creation tests verify core attributes

### Assertions
- [ ] Use conditional assertions for AWS-specific behavior
- [ ] Validate core functionality in both modes
- [ ] Relax validation for LocalStack differences (ARNs, URLs)
- [ ] Document any LocalStack-specific workarounds

### Validation
- [ ] Test passes with `terraform test -var="use_localstack=true"`
- [ ] Test passes with `terraform test -var="use_localstack=false"` (if AWS available)
- [ ] No hardcoded AWS-specific values (account IDs, regions)
- [ ] Compatible with both modes or properly documented as AWS-only

### Documentation
- [ ] Compatibility level accurately reflects test requirements
- [ ] AWS-only features clearly marked in comments
- [ ] LocalStack limitations documented in assertions

## Common Scenarios

### Scenario 1: Parsing Tests (FULL Compatibility)

Parsing tests work identically in both modes:

```hcl
# S3 Event Parsing Tests
# LocalStack Compatibility: FULL
# Tests parse serverless.yml, no AWS resources created

provider "aws" {
  # ... standard dual-mode config
}

run "s3_event_parsing" {
  command = plan

  variables {
    config_path = "tests/fixtures/s3-events.yml"
  }

  # Parsing logic works identically
  assert {
    condition     = length(local.s3_events) == 3
    error_message = "Expected 3 S3 events"
  }
}
```

### Scenario 2: Resource Creation (FULL Compatibility)

Basic resource creation works in LocalStack:

```hcl
# Lambda Function Creation Tests
# LocalStack Compatibility: FULL
# Basic Lambda resource creation supported in LocalStack

provider "aws" {
  # ... standard dual-mode config
}

run "lambda_creation" {
  command = plan

  variables {
    config_path = "tests/fixtures/lambda-basic.yml"
  }

  # Core resource validation
  assert {
    condition     = length(aws_lambda_function.functions) > 0
    error_message = "Lambda functions should be created"
  }

  # Relaxed ARN validation
  assert {
    condition = var.use_localstack || can(regex("^arn:aws:lambda:", aws_lambda_function.functions["hello"].arn))
    error_message = "Lambda ARN format (relaxed in LocalStack)"
  }
}
```

### Scenario 3: Advanced Features (PARTIAL Compatibility)

Some features require AWS:

```hcl
# IAM Advanced Features Tests
# LocalStack Compatibility: PARTIAL
# Basic IAM works in LocalStack, permission boundaries require AWS

provider "aws" {
  # ... standard dual-mode config
}

run "iam_basic_role" {
  command = plan

  variables {
    config_path = "tests/fixtures/iam-basic.yml"
  }

  # Works in both modes
  assert {
    condition     = aws_iam_role.lambda.name != null
    error_message = "IAM role should have a name"
  }
}

run "iam_permission_boundary" {
  command = plan

  variables {
    config_path = "tests/fixtures/iam-boundary.yml"
  }

  # AWS-only feature, skip in LocalStack
  assert {
    condition = var.use_localstack || aws_iam_role.lambda.permissions_boundary != null
    error_message = "Permission boundary should be set (AWS only)"
  }
}
```

## Troubleshooting

### Issue: S3 Bucket Operations Fail in LocalStack

**Solution:** Ensure `s3_use_path_style = var.use_localstack` in provider config.

```hcl
provider "aws" {
  # ... other config
  s3_use_path_style = var.use_localstack  # CRITICAL for LocalStack
}
```

### Issue: IAM Validation Errors in LocalStack

**Solution:** Use conditional assertions to relax IAM validation:

```hcl
assert {
  condition = var.use_localstack || can(regex("^arn:aws:iam::", resource.arn))
  error_message = "IAM ARN validation (relaxed in LocalStack)"
}
```

### Issue: API Gateway URL Format Differs

**Solution:** Check for different URL formats based on mode:

```hcl
assert {
  condition = (
    var.use_localstack && can(regex("localhost", url)) ||
    !var.use_localstack && can(regex("execute-api", url))
  )
  error_message = "URL format differs between LocalStack and AWS"
}
```

### Issue: Test Passes in LocalStack, Fails in AWS

**Cause:** LocalStack validation is less strict than AWS.

**Solution:** Add stricter AWS-specific assertions:

```hcl
# LocalStack: permissive check
assert {
  condition     = resource.arn != null
  error_message = "Resource should have ARN"
}

# AWS: strict format check
assert {
  condition = var.use_localstack || can(regex("^arn:aws:", resource.arn))
  error_message = "AWS ARN should have proper format (AWS only)"
}
```

### Issue: EventBridge Patterns Don't Work in LocalStack

**Cause:** LocalStack Community Edition has limited EventBridge pattern support.

**Solution:** Mark test as PARTIAL and skip complex patterns:

```hcl
# LocalStack Compatibility: PARTIAL
# Complex EventBridge patterns require AWS

assert {
  condition = var.use_localstack || can(regex("complex-pattern", rule.event_pattern))
  error_message = "Complex EventBridge pattern (AWS only)"
}
```

## References

- [LocalStack Setup Guide](./localstack-setup.md)
- [Provider Configuration Guide](./localstack-provider-config.md)
- [LocalStack Service Coverage](https://docs.localstack.cloud/user-guide/aws/feature-coverage/)
- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
