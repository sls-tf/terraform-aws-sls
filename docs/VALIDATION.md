# Validation Guide

This guide explains how validation works in the Serverless-to-Terraform module and how to interpret and resolve validation errors.

## Table of Contents

- [Overview](#overview)
- [How Validation Works](#how-validation-works)
- [Understanding Validation Errors](#understanding-validation-errors)
- [Common Validation Failures](#common-validation-failures)
- [Resolving Errors](#resolving-errors)
- [Disabling Validation](#disabling-validation)

## Overview

The module validates your `serverless.yml` configuration against the official Serverless Framework JSON schema before generating Terraform resources. This catches configuration errors early and provides helpful error messages.

### Benefits

✅ **Early Error Detection**: Catch configuration errors before Terraform plan/apply
✅ **Clear Error Messages**: Detailed messages with schema references and suggestions
✅ **Version-Specific**: Validation matches your Serverless Framework version
✅ **Comprehensive**: Validates required fields, types, enums, patterns, and ranges

## How Validation Works

### 1. Configuration Parsing

The module parses your `serverless.yml`:

```hcl
module "serverless" {
  source = "./path/to/module"

  serverless_config = file("${path.module}/serverless.yml")
  # ... other variables
}
```

### 2. Version Detection

The module detects your Serverless Framework version:

```yaml
# serverless.yml
frameworkVersion: '3'  # Determines which validation rules to use
```

Supported versions:
- `'2'` or `'2.x'` → Uses `validation-v2.tf`
- `'3'` or `'3.x'` → Uses `validation-v3.tf`
- `'4'` or `'4.x'` → Uses `validation-v4.tf`
- Default: `'3'`

### 3. Validation Execution

The module runs validation checks during `terraform plan`:

```hcl
locals {
  # Version-specific validation
  validation_errors = concat(
    local.v3_validation_errors,  # From generated/validation-v3.tf
    local.custom_validation_errors,  # Custom checks
    []
  )

  # Filter out empty strings
  filtered_errors = [for err in local.validation_errors : err if err != ""]
}

# Fail plan if errors exist
resource "terraform_data" "validation" {
  count = length(local.filtered_errors) > 0 ? 1 : 0

  lifecycle {
    precondition {
      condition     = length(local.filtered_errors) == 0
      error_message = join("\n\n", local.filtered_errors)
    }
  }
}
```

### 4. Error Reporting

If validation fails, Terraform displays all errors:

```
Error: Resource precondition failed

│ Required field 'runtime' is missing. AWS Lambda requires a runtime specification.
│ See: https://www.serverless.com/framework/docs/providers/aws/guide/serverless.yml#runtime
│ (Schema: #/properties/provider/required)
│
│ Invalid region. Must be one of: [us-east-1, us-west-2, eu-west-1, ...], got: 'us-east'.
│ Common typo: use "us-east-1" not "us-east".
│ (Schema: #/properties/provider/properties/region/enum)
```

## Understanding Validation Errors

### Error Message Format

Each validation error includes:

1. **Error Description**: What's wrong
2. **Expected vs Actual**: What was expected and what was found
3. **Helpful Suggestion**: Common fixes (when applicable)
4. **Documentation Link**: Link to relevant Serverless Framework docs
5. **Schema Path**: JSON schema location for reference

**Example:**

```
Invalid runtime. Must be one of: [nodejs18.x, nodejs16.x, python3.11], got: 'node18'.
Common typo: use "nodejs18.x" not "node18.x".
See: https://www.serverless.com/framework/docs/providers/aws/guide/serverless.yml#runtime
(Schema: #/properties/provider/properties/runtime/enum)
```

**Breakdown:**
- **Error**: Invalid runtime value
- **Expected**: One of the listed runtimes
- **Actual**: 'node18'
- **Suggestion**: Use "nodejs18.x" instead
- **Docs**: Link to runtime documentation
- **Schema**: Where constraint is defined

### Validation Types

#### 1. Required Field Validation

Ensures mandatory fields are present:

```
Required field 'service' is missing.
The service name is required for all Serverless Framework configurations.
See: https://www.serverless.com/framework/docs/providers/aws/guide/serverless.yml#service
(Schema: #/properties/service/required)
```

**Fix:**
```yaml
service: my-service  # Add missing field
```

#### 2. Type Validation

Ensures fields have correct types:

```
Field 'memorySize' must be of type 'number', got: string.
Memory size must be a number representing MB.
(Schema: #/properties/functions/properties/memorySize/type)
```

**Fix:**
```yaml
functions:
  myFunction:
    memorySize: 512  # Use number, not "512"
```

#### 3. Enum Validation

Ensures values are from allowed list:

```
Invalid architecture. Must be one of: [x86_64, arm64], got: 'arm'.
(Schema: #/properties/provider/properties/architecture/enum)
```

**Fix:**
```yaml
provider:
  architecture: arm64  # Use exact enum value
```

#### 4. Pattern Validation

Ensures strings match required patterns:

```
Field 'functionName' does not match required pattern: ^[a-zA-Z0-9-_]+$.
Function names can only contain alphanumeric characters, hyphens, and underscores.
(Schema: #/properties/functions/patternProperties/pattern)
```

**Fix:**
```yaml
functions:
  my-function:  # Use valid characters only
```

#### 5. Range Validation

Ensures numbers are within valid ranges:

```
memorySize must be at least 128 and at most 10240, got: 64.
AWS Lambda memory must be between 128 MB and 10,240 MB.
(Schema: #/properties/functions/properties/memorySize/minimum)
```

**Fix:**
```yaml
functions:
  myFunction:
    memorySize: 128  # Use value within range
```

## Common Validation Failures

### 1. Missing Runtime

**Error:**
```
Required field 'runtime' is missing.
```

**Cause:** No runtime specified in provider or function

**Fix:**
```yaml
provider:
  name: aws
  runtime: nodejs18.x  # Add runtime
```

### 2. Invalid Runtime Version

**Error:**
```
Invalid runtime. Must be one of: [nodejs18.x, nodejs16.x, ...], got: 'node18'.
Common typo: use "nodejs18.x" not "node18.x".
```

**Cause:** Runtime name doesn't match AWS Lambda format

**Fix:**
```yaml
provider:
  runtime: nodejs18.x  # Use exact runtime name
```

### 3. Invalid Region

**Error:**
```
Invalid region. Must be one of: [us-east-1, us-west-2, ...], got: 'us-east'.
```

**Cause:** Region name incomplete or misspelled

**Fix:**
```yaml
provider:
  region: us-east-1  # Use complete region name
```

### 4. Missing Service Name

**Error:**
```
Required field 'service' is missing.
```

**Cause:** No service name defined

**Fix:**
```yaml
service: my-service  # Add service name at top of file
```

### 5. Invalid Memory Size

**Error:**
```
memorySize must be at least 128, got: 64.
```

**Cause:** Memory below AWS Lambda minimum

**Fix:**
```yaml
functions:
  myFunction:
    memorySize: 128  # Use minimum 128 MB
```

### 6. Invalid Timeout

**Error:**
```
timeout must be at most 900, got: 1000.
```

**Cause:** Timeout exceeds Lambda maximum (15 minutes)

**Fix:**
```yaml
functions:
  myFunction:
    timeout: 900  # Maximum 900 seconds (15 minutes)
```

### 7. Type Mismatch

**Error:**
```
Field 'memorySize' must be of type 'number', got: string.
```

**Cause:** Value is quoted when it should be numeric

**Fix:**
```yaml
functions:
  myFunction:
    memorySize: 512  # No quotes for numbers
```

### 8. Invalid Architecture

**Error:**
```
Invalid architecture. Must be one of: [x86_64, arm64], got: 'amd64'.
```

**Cause:** Architecture name doesn't match AWS format

**Fix:**
```yaml
provider:
  architecture: x86_64  # Use AWS architecture name
```

## Resolving Errors

### Step 1: Read the Error Message

Error messages include:
- What's wrong
- What's expected
- Common fixes
- Documentation links

### Step 2: Check Your serverless.yml

Find the problematic field:

```yaml
provider:
  name: aws
  runtime: node18  # ← Error is here
```

### Step 3: Consult Documentation

Use the provided link:

```
See: https://www.serverless.com/framework/docs/providers/aws/guide/serverless.yml#runtime
```

### Step 4: Apply Fix

Correct the configuration:

```yaml
provider:
  name: aws
  runtime: nodejs18.x  # ✓ Fixed
```

### Step 5: Re-run Terraform Plan

```bash
terraform plan
```

### Multiple Errors

If you have multiple errors, fix them all before re-running:

```
Error: Resource precondition failed

│ 1. Required field 'service' is missing.
│ 2. Invalid runtime: 'node18'
│ 3. Invalid region: 'us-east'
```

Fix all three:

```yaml
service: my-service           # Fix #1
provider:
  name: aws
  runtime: nodejs18.x          # Fix #2
  region: us-east-1            # Fix #3
```

## Disabling Validation

### Not Recommended

Validation catches configuration errors early. Disabling it may lead to:
- Terraform plan failures
- AWS resource creation errors
- Runtime errors

### If You Must Disable

Create a variable to skip validation:

```hcl
variable "skip_validation" {
  description = "Skip configuration validation (not recommended)"
  type        = bool
  default     = false
}

resource "terraform_data" "validation" {
  count = !var.skip_validation && length(local.filtered_errors) > 0 ? 1 : 0

  lifecycle {
    precondition {
      condition     = length(local.filtered_errors) == 0
      error_message = join("\n\n", local.filtered_errors)
    }
  }
}
```

Use:

```bash
terraform plan -var="skip_validation=true"
```

### Selective Disabling

To disable specific validation rules, create a filtered version:

```hcl
locals {
  # Filter out specific validation types
  validation_errors = [
    for err in local.v3_validation_errors :
    err if !can(regex("pattern you want to ignore", err))
  ]
}
```

## Validation in CI/CD

### Pre-Plan Validation

Run validation before Terraform:

```bash
# Validate serverless.yml syntax
npm install -g serverless
serverless print

# Then run Terraform
terraform plan
```

### GitHub Actions Example

```yaml
- name: Validate Serverless Config
  run: |
    npm install -g serverless
    serverless print

- name: Terraform Plan
  run: terraform plan
```

### Handling Validation Failures

```yaml
- name: Terraform Plan
  id: plan
  run: terraform plan
  continue-on-error: true

- name: Comment PR with Errors
  if: steps.plan.outcome == 'failure'
  uses: actions/github-script@v6
  with:
    script: |
      github.rest.issues.createComment({
        issue_number: context.issue.number,
        body: '❌ Configuration validation failed. See plan output for details.'
      })
```

## Advanced Topics

### Custom Validation Rules

Add your own validation alongside generated rules:

```hcl
locals {
  # Custom validation
  custom_validation = [
    for fn in local.functions :
    fn.memorySize % 64 != 0 ?
      "Function '${fn.name}' memory must be multiple of 64 MB" :
      ""
  ]

  # Combine with generated
  all_errors = concat(
    local.v3_validation_errors,
    local.custom_validation
  )
}
```

### Version-Specific Handling

Handle version differences:

```hcl
locals {
  framework_version = try(local.parsed_config.frameworkVersion, "3")

  validation_errors = (
    framework_version == "2" ? local.v2_validation_errors :
    framework_version == "3" ? local.v3_validation_errors :
    framework_version == "4" ? local.v4_validation_errors :
    local.v3_validation_errors  # default
  )
}
```

## Getting Help

- **Error Not Clear**: Open GitHub issue with error message
- **False Positive**: Report as bug with configuration example
- **Feature Request**: Suggest validation improvements
- **Schema Questions**: See [Serverless Framework Docs](https://www.serverless.com/framework/docs/)

## Summary

**Key Points:**

1. ✅ Validation catches errors early
2. 📝 Error messages include fixes and documentation
3. 🔍 Check the schema path for constraint details
4. 📚 Use provided documentation links
5. 🧪 Test after fixing each error

Validation helps ensure your Serverless Framework configuration is correct before deploying to AWS!
