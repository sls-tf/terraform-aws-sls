# LocalStack Variables Reference

Complete reference for LocalStack-related variables in this Terraform module.

## Table of Contents

- [Overview](#overview)
- [Variable Definitions](#variable-definitions)
- [Usage Examples](#usage-examples)
- [Configuration Patterns](#configuration-patterns)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

## Overview

This module uses two variables to control LocalStack integration:

| Variable | Purpose | Default | Required |
|----------|---------|---------|----------|
| `use_localstack` | Enable LocalStack mode | `false` | No |
| `localstack_endpoint` | LocalStack endpoint URL | `http://localhost:4566` | No |

These variables enable dual-mode testing where the same module and tests work with both LocalStack and AWS.

## Variable Definitions

### use_localstack

**Full Definition:**
```hcl
variable "use_localstack" {
  description = "Enable LocalStack mode for testing. When true, configures provider to use LocalStack endpoints instead of AWS."
  type        = bool
  default     = false
}
```

**Purpose:**
Controls whether the module operates in LocalStack or AWS mode. When `true`:
- Provider skips AWS credential validation
- Provider skips metadata API checks
- Provider skips account ID lookup
- S3 path-style access is enabled
- Dynamic endpoint overrides point to LocalStack

**Type:** Boolean (`true` or `false`)

**Default:** `false` (AWS mode)

**When to Use:**
- Local development and testing
- CI/CD pipelines running LocalStack
- Offline development scenarios
- Testing without AWS credentials
- Rapid iteration without AWS costs

**When NOT to Use:**
- Production deployments
- Integration testing against real AWS
- Validating AWS-specific behavior
- Testing IAM permissions
- Performance testing

**Example Usage:**

With Terraform CLI:
```bash
# Enable LocalStack mode
terraform plan -var="use_localstack=true"
terraform test -var="use_localstack=true"

# Explicit AWS mode (default)
terraform plan -var="use_localstack=false"
```

With tfvars file:
```hcl
# terraform.tfvars
use_localstack = true
```

With environment variable:
```bash
export TF_VAR_use_localstack=true
terraform plan
```

### localstack_endpoint

**Full Definition:**
```hcl
variable "localstack_endpoint" {
  description = "LocalStack endpoint URL. Typically http://localhost:4566 for local development or http://localstack:4566 when running in Docker Compose network."
  type        = string
  default     = "http://localhost:4566"

  validation {
    condition     = can(regex("^https?://", var.localstack_endpoint))
    error_message = "The localstack_endpoint must be a valid HTTP or HTTPS URL."
  }
}
```

**Purpose:**
Specifies the base URL for the LocalStack service. All AWS service endpoints will point to this URL when `use_localstack=true`.

**Type:** String (must be valid HTTP/HTTPS URL)

**Default:** `http://localhost:4566`

**Validation:**
- Must start with `http://` or `https://`
- URL format is validated at plan time

**Common Values:**

| Value | Use Case |
|-------|----------|
| `http://localhost:4566` | Local development (default) |
| `http://localstack:4566` | Docker Compose internal network |
| `http://host.docker.internal:4566` | Docker Desktop Mac/Windows |
| `http://172.17.0.1:4566` | Docker Linux host access |
| `http://10.0.0.100:4566` | Remote LocalStack instance |

**When to Override:**

1. **Docker Compose Network:**
   ```bash
   terraform test -var="use_localstack=true" -var="localstack_endpoint=http://localstack:4566"
   ```

2. **Custom Port:**
   ```bash
   terraform test -var="use_localstack=true" -var="localstack_endpoint=http://localhost:8080"
   ```

3. **Remote LocalStack:**
   ```bash
   terraform test -var="use_localstack=true" -var="localstack_endpoint=http://dev-server:4566"
   ```

4. **HTTPS LocalStack (Pro):**
   ```bash
   terraform test -var="use_localstack=true" -var="localstack_endpoint=https://localhost:4566"
   ```

**Example Usage:**

With Terraform CLI:
```bash
terraform plan \
  -var="use_localstack=true" \
  -var="localstack_endpoint=http://localstack:4566"
```

With tfvars file:
```hcl
# terraform.tfvars
use_localstack      = true
localstack_endpoint = "http://localstack:4566"
```

With environment variables:
```bash
export TF_VAR_use_localstack=true
export TF_VAR_localstack_endpoint="http://localstack:4566"
terraform plan
```

## Usage Examples

### Example 1: Local Development

Most common scenario - testing locally with default LocalStack:

```bash
# Start LocalStack
make localstack-start

# Run tests
terraform test -var="use_localstack=true"

# Or run module
terraform init
terraform plan -var="use_localstack=true"
terraform apply -var="use_localstack=true"
```

**Variables:**
- `use_localstack = true`
- `localstack_endpoint = "http://localhost:4566"` (default)

### Example 2: CI/CD Pipeline

GitHub Actions or similar CI system:

```yaml
# .github/workflows/test.yml
- name: Start LocalStack
  run: docker-compose -f docker-compose.localstack.yml up -d

- name: Run Terraform tests
  run: terraform test -var="use_localstack=true"
```

**Variables:**
- `use_localstack = true`
- `localstack_endpoint = "http://localhost:4566"` (default)

### Example 3: Docker Compose Network

When running Terraform inside Docker alongside LocalStack:

```yaml
# docker-compose.yml
services:
  localstack:
    image: localstack/localstack:latest
    ports:
      - "4566:4566"

  terraform:
    image: hashicorp/terraform:latest
    environment:
      - TF_VAR_use_localstack=true
      - TF_VAR_localstack_endpoint=http://localstack:4566
    depends_on:
      - localstack
```

**Variables:**
- `use_localstack = true`
- `localstack_endpoint = "http://localstack:4566"` (container name)

### Example 4: Remote LocalStack

Testing against LocalStack instance on another machine:

```bash
# Terminal 1 (Remote machine 10.0.0.100)
docker run -p 4566:4566 localstack/localstack

# Terminal 2 (Development machine)
terraform test \
  -var="use_localstack=true" \
  -var="localstack_endpoint=http://10.0.0.100:4566"
```

**Variables:**
- `use_localstack = true`
- `localstack_endpoint = "http://10.0.0.100:4566"`

### Example 5: Production (AWS)

Deploy to real AWS (default behavior):

```bash
# No special variables needed
terraform init
terraform plan
terraform apply

# Or explicitly disable LocalStack
terraform plan -var="use_localstack=false"
```

**Variables:**
- `use_localstack = false` (default)
- `localstack_endpoint` is ignored

### Example 6: Mixed Testing

Test suite that runs both LocalStack and AWS:

```bash
# Test with LocalStack
make localstack-start
terraform test -var="use_localstack=true" | tee results-localstack.txt

# Test with AWS (requires credentials)
terraform test -var="use_localstack=false" | tee results-aws.txt

# Compare results
diff results-localstack.txt results-aws.txt
```

**Variables:**
- Run 1: `use_localstack = true`
- Run 2: `use_localstack = false`

### Example 7: Using tfvars File

Create reusable configuration:

```hcl
# localstack.tfvars
use_localstack      = true
localstack_endpoint = "http://localhost:4566"

# AWS settings (if module has other variables)
aws_region = "us-east-1"
environment = "test"
```

Use with:
```bash
terraform plan -var-file="localstack.tfvars"
terraform test -var-file="localstack.tfvars"
```

## Configuration Patterns

### Pattern 1: Development vs. Production

Separate variable files for each environment:

**localstack.tfvars:**
```hcl
use_localstack      = true
localstack_endpoint = "http://localhost:4566"
```

**production.tfvars:**
```hcl
use_localstack = false
# Production-specific variables...
```

**Usage:**
```bash
# Development
terraform plan -var-file="localstack.tfvars"

# Production
terraform plan -var-file="production.tfvars"
```

### Pattern 2: Environment Variable Defaults

Set defaults in shell profile:

```bash
# ~/.bashrc or ~/.zshrc
export TF_VAR_use_localstack=true
export TF_VAR_localstack_endpoint="http://localhost:4566"

# Override for production
alias tf-prod='TF_VAR_use_localstack=false terraform'
```

**Usage:**
```bash
# Uses LocalStack (from env vars)
terraform plan

# Uses AWS (override)
tf-prod plan
```

### Pattern 3: Conditional Provider Configuration

In test files:

```hcl
provider "aws" {
  region = "us-east-1"

  # Only when using LocalStack
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack
  s3_use_path_style          = var.use_localstack

  # Dynamic endpoint override
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

### Pattern 4: Conditional Test Assertions

Adjust test expectations based on environment:

```hcl
assert {
  condition = var.use_localstack ? (
    # LocalStack expectation
    can(regex("localhost:4566", resource.url))
  ) : (
    # AWS expectation
    can(regex("amazonaws\\.com", resource.url))
  )
  error_message = "Invalid resource URL"
}
```

### Pattern 5: Makefile Integration

Convenient commands:

```makefile
# Makefile
test-local:
	terraform test -var="use_localstack=true"

test-aws:
	terraform test -var="use_localstack=false"

test-all: test-local test-aws
	@echo "All tests complete"
```

**Usage:**
```bash
make test-local   # LocalStack
make test-aws     # AWS
make test-all     # Both
```

## Best Practices

### 1. Default to AWS Mode

Keep `use_localstack=false` as default to prevent accidental LocalStack use in production:

```hcl
variable "use_localstack" {
  description = "Enable LocalStack mode for testing"
  type        = bool
  default     = false  # Safe default
}
```

### 2. Explicit Variable Passing

Be explicit when using LocalStack:

```bash
# Good - clear intent
terraform test -var="use_localstack=true"

# Avoid - relies on env vars
# (unless documented in project)
terraform test
```

### 3. Document Variable Usage

In module README or test documentation:

```markdown
## Testing

### Local Testing with LocalStack
terraform test -var="use_localstack=true"

### Testing with AWS
terraform test -var="use_localstack=false"
```

### 4. Validate Endpoint URL

The module includes validation, but also verify in scripts:

```bash
#!/bin/bash
ENDPOINT="${TF_VAR_localstack_endpoint:-http://localhost:4566}"

# Verify LocalStack is running
if ! curl -sf "${ENDPOINT}/_localstack/health" > /dev/null; then
  echo "Error: LocalStack not available at ${ENDPOINT}"
  exit 1
fi

terraform test -var="use_localstack=true" -var="localstack_endpoint=${ENDPOINT}"
```

### 5. Separate Test Fixtures

Use different fixtures for LocalStack vs AWS:

```
tests/
├── fixtures/
│   ├── localstack/      # LocalStack-specific
│   │   └── serverless.yml
│   └── aws/             # AWS-specific
│       └── serverless.yml
└── test.tftest.hcl
```

### 6. Version Control Variable Files

**.gitignore:**
```
# Ignore personal LocalStack config
localstack.auto.tfvars
*.local.tfvars

# Keep shared LocalStack config
!localstack.tfvars.example
```

**localstack.tfvars.example:**
```hcl
# Copy to localstack.auto.tfvars and customize
use_localstack      = true
localstack_endpoint = "http://localhost:4566"
```

### 7. CI/CD Variable Management

Use GitHub Actions secrets or similar for flexible configuration:

```yaml
- name: Run tests
  env:
    TF_VAR_use_localstack: ${{ secrets.USE_LOCALSTACK }}
    TF_VAR_localstack_endpoint: ${{ secrets.LOCALSTACK_ENDPOINT }}
  run: terraform test
```

## Troubleshooting

### Issue: Variables Not Being Applied

**Symptom:** Test behavior doesn't change when passing variables

**Diagnosis:**
```bash
# Check variable is passed
terraform test -var="use_localstack=true" -json | jq '.variables'
```

**Fixes:**

1. **Variable not defined:**
   ```bash
   # Check variables.tf
   grep "use_localstack" variables.tf
   ```

2. **Syntax error in test:**
   ```hcl
   # Wrong:
   skip_credentials_validation = use_localstack

   # Correct:
   skip_credentials_validation = var.use_localstack
   ```

3. **Variable precedence:**
   ```bash
   # Order of precedence (highest to lowest):
   # 1. -var command line flag
   # 2. *.auto.tfvars files
   # 3. terraform.tfvars file
   # 4. TF_VAR_* environment variables
   # 5. Variable defaults
   ```

### Issue: Endpoint Validation Fails

**Symptom:**
```
Error: Invalid value for variable
The localstack_endpoint must be a valid HTTP or HTTPS URL.
```

**Fixes:**

1. **Missing protocol:**
   ```bash
   # Wrong:
   -var="localstack_endpoint=localhost:4566"

   # Correct:
   -var="localstack_endpoint=http://localhost:4566"
   ```

2. **Trailing slash:**
   ```bash
   # Both are valid:
   -var="localstack_endpoint=http://localhost:4566"
   -var="localstack_endpoint=http://localhost:4566/"
   ```

### Issue: LocalStack Not Accessible

**Symptom:** Tests fail with connection errors despite `use_localstack=true`

**Diagnosis:**
```bash
# Check LocalStack is running
curl http://localhost:4566/_localstack/health

# Check endpoint variable
echo $TF_VAR_localstack_endpoint
```

**Fixes:**

1. **LocalStack not running:**
   ```bash
   make localstack-start
   ```

2. **Wrong endpoint:**
   ```bash
   # Check which endpoint LocalStack is on
   docker ps | grep localstack
   # Adjust variable to match
   ```

3. **Network isolation:**
   ```bash
   # If running in Docker, use container name
   -var="localstack_endpoint=http://localstack:4566"
   ```

### Issue: Variables Work in Plan but Not Test

**Symptom:** `terraform plan` works but `terraform test` fails

**Cause:** Test files need provider configuration

**Fix:**
Ensure test file includes provider block with variable references:

```hcl
provider "aws" {
  region = "us-east-1"
  skip_credentials_validation = var.use_localstack
  s3_use_path_style = var.use_localstack

  dynamic "endpoints" {
    for_each = var.use_localstack ? [1] : []
    content {
      s3 = var.localstack_endpoint
    }
  }
}
```

### Issue: Can't Override Default Endpoint

**Symptom:** Custom endpoint ignored, always uses localhost:4566

**Diagnosis:**
```bash
# Check what value is being used
TF_LOG=DEBUG terraform test -var="use_localstack=true" -var="localstack_endpoint=http://custom:4566" 2>&1 | grep endpoint
```

**Cause:** Variable precedence issue

**Fix:**
```bash
# Clear conflicting environment variable
unset TF_VAR_localstack_endpoint

# Pass explicitly
terraform test -var="use_localstack=true" -var="localstack_endpoint=http://custom:4566"
```

## Quick Reference

### Command Cheat Sheet

```bash
# Local development (default endpoint)
terraform test -var="use_localstack=true"

# Custom endpoint
terraform test \
  -var="use_localstack=true" \
  -var="localstack_endpoint=http://localstack:4566"

# AWS mode (explicit)
terraform test -var="use_localstack=false"

# With tfvars file
terraform test -var-file="localstack.tfvars"

# Check variable values
terraform console -var="use_localstack=true"
> var.use_localstack
true
> var.localstack_endpoint
"http://localhost:4566"
```

### Variable Summary Table

| Variable | Type | Default | Validated | Required |
|----------|------|---------|-----------|----------|
| `use_localstack` | bool | `false` | No | No |
| `localstack_endpoint` | string | `http://localhost:4566` | Yes | No |

### Provider Configuration Reference

```hcl
provider "aws" {
  region                      = "us-east-1"
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack
  s3_use_path_style          = var.use_localstack

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

## Related Documentation

- [LocalStack Setup Guide](./localstack-setup.md)
- [LocalStack Testing Guide](./localstack-testing.md)
- [Test Migration Guide](./localstack-test-migration.md)
- [Troubleshooting Guide](./localstack-troubleshooting.md)
- [Provider Configuration](./localstack-provider-config.md)
