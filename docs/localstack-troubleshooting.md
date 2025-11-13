# LocalStack Troubleshooting Guide

Comprehensive troubleshooting guide for LocalStack integration issues.

## Table of Contents

- [Quick Diagnostics](#quick-diagnostics)
- [Infrastructure Issues](#infrastructure-issues)
- [Test Execution Issues](#test-execution-issues)
- [Service-Specific Issues](#service-specific-issues)
- [Configuration Issues](#configuration-issues)
- [Performance Issues](#performance-issues)
- [Common Error Messages](#common-error-messages)
- [Debug Techniques](#debug-techniques)
- [Getting Help](#getting-help)

## Quick Diagnostics

Run these commands first to identify common issues:

```bash
# 1. Check Docker is running
docker ps
# Should show running containers without errors

# 2. Check LocalStack container status
docker-compose -f docker-compose.localstack.yml ps
# Should show: sls-tf-localstack Up (healthy)

# 3. Check LocalStack health endpoint
curl http://localhost:4566/_localstack/health | jq
# Should return JSON with service statuses

# 4. Check port availability
lsof -i :4566
# Should show LocalStack or nothing if not running

# 5. Check LocalStack logs for errors
make localstack-logs | tail -n 50
# Look for ERROR or WARNING messages
```

### Health Check Script

Create a quick diagnostic script:

```bash
#!/bin/bash
# localstack-diagnostic.sh

echo "=== LocalStack Diagnostics ==="
echo ""

echo "1. Docker Status:"
docker ps --filter "name=localstack" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""

echo "2. Port 4566:"
lsof -i :4566 || echo "Port 4566 is available"
echo ""

echo "3. Health Endpoint:"
curl -s http://localhost:4566/_localstack/health | jq '.services' || echo "Health check failed"
echo ""

echo "4. Recent Logs (last 20 lines):"
docker logs --tail 20 sls-tf-localstack 2>&1
echo ""

echo "=== Diagnostics Complete ==="
```

Run with:
```bash
chmod +x localstack-diagnostic.sh
./localstack-diagnostic.sh
```

## Infrastructure Issues

### Issue: LocalStack Won't Start

**Symptoms:**
- `make localstack-start` hangs or times out
- Container status shows "Restarting" or "Exited"
- Health check never returns healthy

**Diagnosis:**
```bash
# Check container status
docker-compose -f docker-compose.localstack.yml ps

# Check logs for startup errors
docker logs sls-tf-localstack
```

**Common Causes:**

#### 1. Docker Not Running

**Check:**
```bash
docker ps
# Error: Cannot connect to Docker daemon
```

**Fix:**
```bash
# Linux
sudo systemctl start docker
sudo systemctl status docker

# Mac/Windows
# Start Docker Desktop application
```

#### 2. Port 4566 Already in Use

**Check:**
```bash
lsof -i :4566
# Shows another process using the port
```

**Fix:**
```bash
# Kill the other process
kill -9 <PID>

# Or change LocalStack port in docker-compose.localstack.yml
ports:
  - "4567:4566"  # Use different external port
```

#### 3. Docker Compose Not Found

**Symptoms:**
```
docker-compose: command not found
```

**Fix:**

For Docker Compose V2:
```bash
# V2 uses 'docker compose' (no hyphen)
docker compose version

# Update Makefile if needed
```

For Docker Compose V1:
```bash
# Install V1
pip install docker-compose

# Or upgrade to Docker Desktop with V2 built-in
```

#### 4. Insufficient Docker Resources

**Symptoms:**
- LocalStack starts but services fail
- Out of memory errors in logs
- Container keeps restarting

**Fix:**
```bash
# Check Docker resource limits
docker info | grep -i memory
docker info | grep -i cpu

# Increase resources in Docker Desktop:
# Settings → Resources → Advanced
# Recommended: 4GB RAM, 2 CPUs minimum
```

#### 5. Image Pull Issues

**Symptoms:**
```
Error response from daemon: Get "https://registry...": dial tcp: lookup...
```

**Fix:**
```bash
# Pull image manually
docker pull localstack/localstack:latest

# Or use specific version
docker pull localstack/localstack:3.0

# Update docker-compose.localstack.yml
image: localstack/localstack:3.0
```

### Issue: Container Starts but Becomes Unhealthy

**Symptoms:**
- Container shows "Up" but health check fails
- Services not responding

**Diagnosis:**
```bash
# Check health status
docker inspect sls-tf-localstack | jq '.[0].State.Health'

# Check what health check is testing
docker inspect sls-tf-localstack | jq '.[0].Config.Healthcheck'
```

**Common Causes:**

#### 1. Services Not Loading

**Check logs:**
```bash
docker logs sls-tf-localstack | grep -i "service"
```

**Fix:**
```yaml
# In docker-compose.localstack.yml
environment:
  - EAGER_SERVICE_LOADING=1  # Load all services at startup
  - SERVICES=lambda,apigateway,s3,iam,dynamodb,sqs,sns,events,route53
```

#### 2. Slow Service Initialization

**Fix:**
```bash
# Increase health check timeout in Makefile
HEALTH_TIMEOUT ?= 120  # Increase from 60 to 120 seconds
```

## Test Execution Issues

### Issue: Tests Fail with Connection Errors

**Symptoms:**
```
Error: error configuring Terraform AWS Provider: error validating provider credentials
```

**Diagnosis:**
```bash
# Check if LocalStack is accessible
curl http://localhost:4566/_localstack/health

# Check provider configuration in test file
grep -A 10 "provider \"aws\"" tests/your_test.tftest.hcl
```

**Common Causes:**

#### 1. Missing Provider Configuration

**Check:**
```hcl
# Test file should have provider block
provider "aws" {
  region = "us-east-1"
  skip_credentials_validation = var.use_localstack
  # ...
}
```

**Fix:**
Add provider configuration from `tests/test_provider_template.txt`

#### 2. Incorrect Endpoint Variable

**Check:**
```bash
# Verify variable defaults
grep -A 3 "localstack_endpoint" variables.tf
```

**Fix:**
```hcl
# variables.tf should have:
variable "localstack_endpoint" {
  description = "LocalStack endpoint URL"
  type        = string
  default     = "http://localhost:4566"
}
```

#### 3. LocalStack Not Running

**Check:**
```bash
docker ps | grep localstack
# Should show running container
```

**Fix:**
```bash
make localstack-start
```

### Issue: Tests Pass in AWS but Fail in LocalStack

**Symptoms:**
- Test succeeds with `use_localstack=false`
- Test fails with `use_localstack=true`
- Assertion errors about URL formats, ARNs, or resource attributes

**Diagnosis:**
```bash
# Run test with verbose output
TF_LOG=DEBUG terraform test -filter="tests/your_test.tftest.hcl" -var="use_localstack=true" 2>&1 | tee debug.log

# Look for assertion failures
grep -A 5 "Assertion failed" debug.log
```

**Common Causes:**

#### 1. Strict URL Format Assertions

**Problem:**
```hcl
# This fails in LocalStack
assert {
  condition = can(regex("execute-api.*amazonaws\\.com", url))
  error_message = "Invalid API Gateway URL"
}
```

**Fix:**
```hcl
# Make conditional
assert {
  condition = var.use_localstack ? (
    can(regex("localhost:4566", url))
  ) : (
    can(regex("execute-api.*amazonaws\\.com", url))
  )
  error_message = "Invalid API Gateway URL"
}
```

#### 2. ARN Format Differences

**Problem:**
LocalStack uses `arn:localstack:` prefix instead of `arn:aws:`

**Fix:**
```hcl
# Change from:
can(regex("^arn:aws:", resource.arn))

# To:
can(regex("^arn:(aws|localstack):", resource.arn))
```

#### 3. Account ID Validation

**Problem:**
LocalStack uses `000000000000` instead of real 12-digit account ID

**Fix:**
```hcl
# Skip validation in LocalStack
assert {
  condition = var.use_localstack || can(regex("^[0-9]{12}$", account_id))
  error_message = "Invalid account ID"
}
```

#### 4. Certificate Validation

**Problem:**
ACM certificates created but not validated in LocalStack

**Fix:**
```hcl
# Relax certificate status check
assert {
  condition = var.use_localstack ? (
    aws_acm_certificate.cert.arn != null
  ) : (
    aws_acm_certificate.cert.status == "ISSUED"
  )
  error_message = "Certificate validation failed"
}
```

### Issue: Tests Timeout

**Symptoms:**
- Test hangs indefinitely
- No error message, just timeout
- Container logs show requests but no completion

**Diagnosis:**
```bash
# Monitor LocalStack logs during test
make localstack-logs &
terraform test -filter="tests/your_test.tftest.hcl" -var="use_localstack=true"
```

**Common Causes:**

#### 1. Lambda Execution Timeout

**Problem:**
Lambda function trying to access external resources

**Fix:**
```yaml
# Mock external dependencies
# Or set shorter timeout in function config
```

#### 2. Service Not Loaded

**Check:**
```bash
curl http://localhost:4566/_localstack/health | jq '.services'
```

**Fix:**
```yaml
# Add service to SERVICES list in docker-compose.localstack.yml
environment:
  - SERVICES=lambda,apigateway,s3,iam,dynamodb,sqs,sns,events,route53,acm
```

#### 3. Resource Dependencies

**Problem:**
Waiting for resource that depends on unsupported feature

**Fix:**
Review test for dependencies on unsupported services and mock or skip them

## Service-Specific Issues

### S3 Issues

#### Issue: S3 Bucket Operations Fail

**Symptoms:**
```
Error: Error creating S3 bucket: BucketAlreadyOwnedByYou
```

**Fix:**
```hcl
provider "aws" {
  s3_use_path_style = var.use_localstack  # MUST be true for LocalStack
}
```

#### Issue: S3 Events Not Triggering

**Symptoms:**
- Bucket notification configuration succeeds
- Events not delivered to Lambda/SNS/SQS

**Diagnosis:**
```bash
# Check notification configuration
aws --endpoint-url=http://localhost:4566 s3api get-bucket-notification-configuration --bucket test-bucket
```

**Fix:**
Event delivery is limited in LocalStack Community. Consider LocalStack Pro or test notification configuration only.

### API Gateway Issues

#### Issue: API Gateway URLs Have Wrong Format

**Symptoms:**
URLs like `http://localhost:4566/restapis/abc123/dev/_user_request_/path` instead of AWS format

**Fix:**
Expected behavior in LocalStack. Adjust assertions:
```hcl
condition = var.use_localstack ? (
  can(regex("localhost:4566", url))
) : (
  can(regex("execute-api", url))
)
```

#### Issue: CORS Not Working

**Symptoms:**
CORS headers configured but not returned

**Diagnosis:**
```bash
# Test API endpoint
curl -H "Origin: http://example.com" http://localhost:4566/restapis/abc123/dev/_user_request_/path -v
```

**Fix:**
CORS in LocalStack requires proper method response configuration. Verify mock integration response includes headers.

### Lambda Issues

#### Issue: Lambda Function Not Found

**Symptoms:**
```
Error: error getting Lambda Function: ResourceNotFoundException
```

**Diagnosis:**
```bash
# List functions
aws --endpoint-url=http://localhost:4566 lambda list-functions

# Check function logs
docker logs sls-tf-localstack | grep lambda
```

**Common Causes:**

1. **Lambda service not loaded**
   ```yaml
   # Ensure lambda in SERVICES
   environment:
     - SERVICES=lambda,...
   ```

2. **Function code not provided**
   ```hcl
   # Test must provide function code
   resource "aws_lambda_function" "test" {
     filename = "test-fixtures/function.zip"
     # or
     s3_bucket = "bucket"
     s3_key    = "function.zip"
   }
   ```

#### Issue: Lambda Execution Fails

**Symptoms:**
Function created but invocation fails

**Diagnosis:**
```bash
# Invoke function directly
aws --endpoint-url=http://localhost:4566 lambda invoke \
  --function-name test-function \
  --payload '{}' \
  response.json

cat response.json
```

**Fix:**
Check function handler and runtime are correct for LocalStack.

### DynamoDB Issues

#### Issue: DynamoDB Streams Not Working

**Symptoms:**
- Stream enabled on table
- Lambda not triggered by stream events

**Fix:**
DynamoDB Streams require LocalStack Pro for full functionality. Use event source mapping validation tests instead.

### SNS/SQS Issues

#### Issue: Topic Subscription Not Delivering

**Symptoms:**
- Subscription created successfully
- Messages published but not received

**Diagnosis:**
```bash
# Check subscription status
aws --endpoint-url=http://localhost:4566 sns list-subscriptions

# Check queue
aws --endpoint-url=http://localhost:4566 sqs receive-message --queue-url http://localhost:4566/000000000000/test-queue
```

**Fix:**
Verify subscription filter policy if used. LocalStack filter policy support is limited.

### IAM Issues

#### Issue: IAM Policy Validation Errors

**Symptoms:**
- Policy created but not validated
- Overly permissive policies accepted

**Fix:**
LocalStack IAM validation is less strict than AWS. Add conditional assertions:
```hcl
assert {
  condition = var.use_localstack || (
    # Strict AWS validation
    can(regex("arn:aws:iam::aws:policy", policy.arn))
  )
  error_message = "Policy validation failed"
}
```

## Configuration Issues

### Issue: Variables Not Being Applied

**Symptoms:**
Test runs but `use_localstack` seems ignored

**Diagnosis:**
```bash
# Check variable is passed
terraform test -var="use_localstack=true" -json | jq '.variables'
```

**Common Causes:**

#### 1. Variable Not Defined in Module

**Check:**
```bash
grep "variable \"use_localstack\"" variables.tf
```

**Fix:**
Add variable definition to `variables.tf`

#### 2. Variable Syntax Error in Test

**Check test file:**
```hcl
# Correct:
skip_credentials_validation = var.use_localstack

# Wrong:
skip_credentials_validation = use_localstack  # Missing 'var.'
```

### Issue: Endpoint Override Not Working

**Symptoms:**
Requests still going to AWS instead of LocalStack

**Diagnosis:**
```bash
# Enable Terraform debug logging
TF_LOG=DEBUG terraform test -var="use_localstack=true" 2>&1 | grep endpoint
```

**Common Causes:**

#### 1. Dynamic Block Not Triggering

**Check:**
```hcl
dynamic "endpoints" {
  for_each = var.use_localstack ? [1] : []  # Must evaluate to non-empty list
  content {
    s3 = var.localstack_endpoint
  }
}
```

#### 2. Service Not Configured in Endpoints

**Fix:**
Add missing service to endpoints block:
```hcl
dynamic "endpoints" {
  for_each = var.use_localstack ? [1] : []
  content {
    acm        = var.localstack_endpoint  # Add if using ACM
    apigateway = var.localstack_endpoint
    # ... all services used in tests
  }
}
```

## Performance Issues

### Issue: Tests Are Slow

**Symptoms:**
- LocalStack tests taking minutes instead of seconds
- Resource creation very slow

**Diagnosis:**
```bash
# Time a simple test
time terraform test -filter="tests/simple_test.tftest.hcl" -var="use_localstack=true"
```

**Common Causes:**

#### 1. LAMBDA_EXECUTOR=docker

**Problem:**
Each Lambda invocation creates new container

**Fix:**
```yaml
# docker-compose.localstack.yml
environment:
  - LAMBDA_EXECUTOR=docker-reuse  # Reuse containers
```

#### 2. Services Loading On-Demand

**Problem:**
Services load when first accessed

**Fix:**
```yaml
environment:
  - EAGER_SERVICE_LOADING=1  # Load all at startup
```

#### 3. No Resource Limits

**Problem:**
LocalStack competing for resources with other processes

**Fix:**
```yaml
services:
  localstack:
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 2048M
        reservations:
          cpus: '1.0'
          memory: 1024M
```

#### 4. Terraform Provider Cache Missing

**Fix:**
```bash
# Enable provider plugin cache
export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"
mkdir -p $TF_PLUGIN_CACHE_DIR
```

### Issue: Container Uses Too Much Memory

**Symptoms:**
- Docker shows high memory usage
- System becomes slow
- Container OOM killed

**Diagnosis:**
```bash
docker stats sls-tf-localstack
```

**Fix:**

1. **Disable persistence:**
   ```yaml
   environment:
     - PERSISTENCE=0
   ```

2. **Limit services:**
   ```yaml
   environment:
     - SERVICES=lambda,apigateway,s3  # Only what you need
   ```

3. **Set memory limit:**
   ```yaml
   deploy:
     resources:
       limits:
         memory: 2048M
   ```

## Common Error Messages

### Error: "No provider configuration found"

**Full Message:**
```
Error: No configuration files

No configuration files were found. Please ensure that your working directory
contains Terraform configuration files.
```

**Cause:** Running terraform test from wrong directory

**Fix:**
```bash
# Run from module root
cd /path/to/sls.tf
terraform test
```

### Error: "health check timeout"

**Full Message:**
```
LocalStack health check timed out after 60 seconds
Container may not be ready
```

**Causes:**
1. Container still starting up
2. Service loading taking too long
3. Container unhealthy

**Fix:**
```bash
# Check container logs
make localstack-logs

# Increase timeout in Makefile
HEALTH_TIMEOUT ?= 120

# Check which services are slow
curl http://localhost:4566/_localstack/health | jq
```

### Error: "BucketAlreadyOwnedByYou"

**Full Message:**
```
Error: Error creating S3 bucket: BucketAlreadyOwnedByYou:
Your previous request to create the named bucket succeeded and you already own it.
```

**Cause:** Bucket exists from previous test run

**Fix:**

1. **Clean up between tests:**
   ```bash
   make localstack-restart  # Restarts with clean state
   ```

2. **Use unique bucket names:**
   ```hcl
   resource "aws_s3_bucket" "test" {
     bucket = "test-bucket-${random_id.suffix.hex}"
   }
   ```

### Error: "InvalidSignatureException"

**Full Message:**
```
Error: error validating credentials: InvalidSignatureException:
The request signature we calculated does not match the signature you provided.
```

**Causes:**
1. `s3_use_path_style` not set
2. Endpoint configuration incorrect
3. AWS credentials interfering

**Fix:**
```hcl
provider "aws" {
  region = "us-east-1"
  s3_use_path_style = var.use_localstack

  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack
}
```

## Debug Techniques

### Enable Terraform Debug Logging

```bash
# Set log level
export TF_LOG=DEBUG
export TF_LOG_PATH=terraform-debug.log

# Run test
terraform test -var="use_localstack=true"

# View log
less terraform-debug.log
```

### Enable LocalStack Debug Mode

```yaml
# docker-compose.localstack.yml
environment:
  - DEBUG=1
  - LS_LOG=trace
```

Restart and check logs:
```bash
make localstack-restart
make localstack-logs
```

### Capture HTTP Traffic

Use LocalStack's endpoint to see all API calls:

```bash
# Enable request logging
docker exec sls-tf-localstack bash -c "echo 'logging.level.localstack.request=DEBUG' >> /etc/localstack/localstack.conf"

# Restart
make localstack-restart

# View requests
make localstack-logs | grep "REQUEST"
```

### Test Provider Configuration Directly

Create minimal test:

```hcl
# test-provider.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style = true

  endpoints {
    s3 = "http://localhost:4566"
  }
}

resource "aws_s3_bucket" "test" {
  bucket = "test-provider-config"
}
```

Test:
```bash
terraform init
terraform plan
# Should succeed without AWS credentials
```

### Test LocalStack Directly with AWS CLI

```bash
# Configure aws-local
pip install awscli-local

# Test S3
awslocal s3 mb s3://test-bucket
awslocal s3 ls

# Test Lambda
awslocal lambda list-functions

# Test API Gateway
awslocal apigateway get-rest-apis
```

### Isolate Test Failures

Binary search approach:

1. **Disable half of assertions:**
   ```hcl
   # Comment out half of assert blocks
   ```

2. **Run test:**
   - Passes? Issue in disabled assertions
   - Fails? Issue in enabled assertions

3. **Repeat until isolated**

## Getting Help

### Check Documentation

1. **LocalStack docs**: https://docs.localstack.cloud/
2. **Service coverage**: https://docs.localstack.cloud/user-guide/aws/feature-coverage/
3. **Configuration**: https://docs.localstack.cloud/references/configuration/
4. **Module docs**: Check `docs/` directory

### Search for Known Issues

```bash
# Search LocalStack GitHub issues
# https://github.com/localstack/localstack/issues

# Common searches:
# - "[service-name] not working"
# - "error message text"
# - "Community Edition limitation"
```

### Enable Verbose Output

When reporting issues, include:

```bash
# 1. Environment info
docker --version
docker-compose --version
terraform --version

# 2. LocalStack health
curl http://localhost:4566/_localstack/health | jq

# 3. Container status
docker ps

# 4. Recent logs
docker logs --tail 100 sls-tf-localstack

# 5. Test output
terraform test -filter="tests/failing_test.tftest.hcl" -var="use_localstack=true" 2>&1
```

### Create Minimal Reproduction

Isolate issue to minimal test case:

```hcl
# minimal-test.tftest.hcl
provider "aws" {
  region = "us-east-1"
  skip_credentials_validation = true
  s3_use_path_style = true
  endpoints {
    s3 = "http://localhost:4566"
  }
}

run "minimal_s3_test" {
  command = apply

  variables {
    # Minimal variables
  }

  assert {
    # Single failing assertion
    condition = true
    error_message = "This should pass"
  }
}
```

### LocalStack Community Support

- **GitHub Discussions**: https://github.com/localstack/localstack/discussions
- **Slack**: https://localstack.cloud/slack
- **Stack Overflow**: Tag with `localstack`

### Module-Specific Issues

For issues with this module specifically:

1. Check compatibility matrix: `docs/localstack-test-matrix.md`
2. Review test migration guide: `docs/localstack-test-migration.md`
3. Verify provider config: `docs/localstack-provider-config.md`
4. Check existing tests for patterns

## Reference

### Useful Commands

```bash
# Quick status
make localstack-status

# Full diagnostic
docker logs sls-tf-localstack
curl http://localhost:4566/_localstack/health | jq
docker stats sls-tf-localstack --no-stream

# Complete reset
make localstack-clean
docker system prune -f
make localstack-start

# Test specific file with debug
TF_LOG=DEBUG terraform test -filter="tests/your_test.tftest.hcl" -var="use_localstack=true"
```

### Configuration Files

| File | Purpose |
|------|---------|
| `docker-compose.localstack.yml` | Container configuration |
| `variables.tf` | LocalStack variables |
| `Makefile` | Lifecycle commands |
| `.localstack/config.yml` | LocalStack settings |
| `tests/test_provider_template.txt` | Provider template |

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `TF_LOG` | Terraform logging level |
| `TF_LOG_PATH` | Log file path |
| `DEBUG` | LocalStack debug mode |
| `LS_LOG` | LocalStack log level |
| `LOCALSTACK_HOST` | Override endpoint |

## Quick Reference Card

Print this for quick troubleshooting:

```
LOCALSTACK QUICK TROUBLESHOOTING

1. Won't start?
   → docker ps
   → docker logs sls-tf-localstack
   → lsof -i :4566

2. Tests fail?
   → make localstack-health
   → Check provider config in test
   → TF_LOG=DEBUG terraform test

3. Slow?
   → LAMBDA_EXECUTOR=docker-reuse
   → EAGER_SERVICE_LOADING=1
   → docker stats sls-tf-localstack

4. S3 errors?
   → s3_use_path_style = true

5. Reset everything:
   → make localstack-clean
   → make localstack-start
```
