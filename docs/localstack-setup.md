# LocalStack Setup Guide

Complete guide for setting up and using LocalStack with this Terraform module.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Configuration](#configuration)
- [Running Tests](#running-tests)
- [Troubleshooting](#troubleshooting)
- [Advanced Usage](#advanced-usage)

## Prerequisites

### Required

- **Docker**: Version 20.10 or later
  ```bash
  docker --version
  # Should output: Docker version 20.10.x or higher
  ```

- **Docker Compose**: Version 2.0 or later
  ```bash
  docker-compose --version
  # Should output: Docker Compose version 2.x.x or higher
  ```

- **Terraform**: Version 1.5 or later
  ```bash
  terraform --version
  # Should output: Terraform v1.5.x or higher
  ```

### Optional

- **Make**: For convenient lifecycle management
  ```bash
  make --version
  # Should output: GNU Make 3.81 or higher
  ```

- **curl**: For health checks
  ```bash
  curl --version
  ```

- **jq**: For JSON parsing in health checks
  ```bash
  jq --version
  ```

## Quick Start

Get LocalStack running in under 2 minutes:

```bash
# 1. Start LocalStack
make localstack-start

# 2. Verify it's healthy
make localstack-health

# 3. Run tests
make test-local
```

That's it! LocalStack is running and tests are executing locally.

## Installation

### Step 1: Clone Repository

```bash
git clone <repository-url>
cd sls.tf
```

### Step 2: Verify Prerequisites

Run the prerequisite checks:

```bash
# Check Docker
docker --version
docker ps  # Should succeed without errors

# Check Docker Compose
docker-compose --version

# Check Terraform
terraform --version
```

### Step 3: Review Configuration

The LocalStack configuration is in `docker-compose.localstack.yml`:

```yaml
services:
  localstack:
    image: localstack/localstack:latest
    ports:
      - "4566:4566"  # Main LocalStack endpoint
    environment:
      - SERVICES=lambda,apigateway,s3,iam,dynamodb,sqs,sns,events,route53
```

**Default Services Enabled:**
- Lambda
- API Gateway
- S3
- IAM
- DynamoDB
- SQS
- SNS
- EventBridge (Events)
- Route 53

### Step 4: Start LocalStack

Using Make (recommended):
```bash
make localstack-start
```

Using Docker Compose directly:
```bash
docker-compose -f docker-compose.localstack.yml up -d
```

The `make localstack-start` command includes:
- Container startup
- Health check with 60-second timeout
- Automatic failure detection with log output

## Configuration

### Environment Variables

LocalStack behavior is controlled via environment variables in `docker-compose.localstack.yml`:

| Variable | Default | Purpose |
|----------|---------|---------|
| `SERVICES` | lambda,apigateway,... | AWS services to enable |
| `LAMBDA_EXECUTOR` | docker-reuse | Lambda execution mode |
| `PERSISTENCE` | 0 | Data persistence (0=off, 1=on) |
| `EAGER_SERVICE_LOADING` | 1 | Load services at startup |
| `DEBUG` | 0 | Enable debug logging |

### Customization

To customize LocalStack configuration:

**Option 1: Modify docker-compose.localstack.yml**

```yaml
environment:
  - SERVICES=lambda,apigateway,s3  # Enable only needed services
  - DEBUG=1  # Enable debug mode
  - PERSISTENCE=1  # Enable data persistence
```

**Option 2: Use .localstack/config.yml**

Create custom configuration:

```yaml
# .localstack/config.yml
debug: true
persistence: true
services:
  - lambda
  - apigateway
  - s3
```

Update docker-compose to mount config:

```yaml
volumes:
  - ./.localstack/config.yml:/etc/localstack/config.yml
```

### Init Scripts

Create initialization scripts that run when LocalStack starts:

```bash
# Create init script
cat > .localstack/init-scripts/01-setup.sh << 'EOF'
#!/bin/bash
# Create test resources
aws --endpoint-url=http://localhost:4566 s3 mb s3://test-bucket
EOF

# Make executable
chmod +x .localstack/init-scripts/01-setup.sh
```

Scripts in `.localstack/init-scripts/` run automatically when LocalStack reaches "ready" state.

## Running Tests

### Using Make (Recommended)

**Run all tests with LocalStack:**
```bash
make test-local
```

**Run specific test file:**
```bash
terraform test -filter="tests/http_event_parsing.tftest.hcl" -var="use_localstack=true"
```

**Run tests matching pattern:**
```bash
terraform test -filter="*parsing*" -var="use_localstack=true"
```

### Without Make

```bash
# Initialize Terraform
terraform init

# Run all tests
terraform test -var="use_localstack=true"

# Run with verbose output
TF_LOG=DEBUG terraform test -var="use_localstack=true"
```

### Interpreting Test Results

Terraform test output shows:

```
tests/http_event_parsing.tftest.hcl... pass
tests/s3_event_parsing.tftest.hcl... pass
tests/api_gateway_resources.tftest.hcl... pass
```

**Status Codes:**
- `pass` - Test succeeded
- `fail` - Test failed (check assertion messages)
- `skip` - Test skipped (likely AWS-only test)

### Test Output

Tests produce detailed output:

```
Success! 16 passed, 0 failed.
```

For failures:

```
Failure! 15 passed, 1 failed.

Failures:

  run "api_gateway_deployment"
    Error: Assertion failed

    on tests/api_gateway_deployment.tftest.hcl line 45:
    condition = can(regex("execute-api", deployment.invoke_url))
    error_message = "Expected AWS-style invoke URL"
```

## Troubleshooting

### LocalStack Won't Start

**Symptom:** `make localstack-start` times out

**Solution:**
```bash
# Check Docker is running
docker ps

# Check container logs
docker-compose -f docker-compose.localstack.yml logs

# Try restarting Docker daemon
sudo systemctl restart docker  # Linux
# or restart Docker Desktop on Mac/Windows
```

### Health Check Fails

**Symptom:** Health check endpoint not responding

**Solution:**
```bash
# Check if port 4566 is available
lsof -i :4566

# Check container status
docker-compose -f docker-compose.localstack.yml ps

# View detailed logs
make localstack-logs

# Try stopping and cleaning
make localstack-clean
make localstack-start
```

### S3 Operations Fail

**Symptom:** S3 bucket creation or operations fail

**Solution:**
Ensure `s3_use_path_style = true` in provider configuration:

```hcl
provider "aws" {
  s3_use_path_style = var.use_localstack
  # ... other settings
}
```

### Tests Pass in AWS but Fail in LocalStack

**Symptom:** Tests work with real AWS but fail with LocalStack

**Common Causes:**

1. **Strict IAM validation** - LocalStack is less strict
2. **URL format differences** - API Gateway URLs differ
3. **Service limitations** - Some features not fully supported

**Solution:** Check test compatibility matrix in `docs/localstack-test-matrix.md`

### Port Already in Use

**Symptom:** `Error: port 4566 is already allocated`

**Solution:**
```bash
# Find process using port
lsof -i :4566

# Kill the process
kill -9 <PID>

# Or stop existing LocalStack
make localstack-stop
```

### Docker Compose Not Found

**Symptom:** `docker-compose: command not found`

**Solution:**

For Docker Compose V2:
```bash
# Use docker compose (no hyphen)
docker compose version

# Update Makefile to use v2 syntax if needed
```

For Docker Compose V1:
```bash
# Install docker-compose
pip install docker-compose
```

## Advanced Usage

### Persistence

Enable data persistence across restarts:

```yaml
# docker-compose.localstack.yml
environment:
  - PERSISTENCE=1

volumes:
  - ./.localstack/data:/tmp/localstack/data
```

### Debug Mode

Enable detailed logging:

```yaml
environment:
  - DEBUG=1
  - LS_LOG=trace
```

View logs:
```bash
make localstack-logs
```

### Service Selection

Enable only needed services for faster startup:

```yaml
environment:
  - SERVICES=lambda,apigateway,s3
```

### Performance Tuning

**Lambda Executor Modes:**

- `docker` - New container per invocation (slower, isolated)
- `docker-reuse` - Reuse containers (faster, recommended)
- `local` - No containers (fastest, less isolated)

```yaml
environment:
  - LAMBDA_EXECUTOR=docker-reuse
```

**Eager Loading:**

Load all services at startup instead of on-demand:

```yaml
environment:
  - EAGER_SERVICE_LOADING=1
```

### Integration with CI/CD

The repository includes GitHub Actions workflow:

```yaml
# .github/workflows/test.yml
- name: Start LocalStack
  run: make localstack-start

- name: Run tests
  run: make test-local
```

See `.github/workflows/test.yml` for complete workflow.

### Using LocalStack CLI

Install LocalStack CLI for advanced management:

```bash
pip install localstack
```

Commands:
```bash
# Check status
localstack status

# View services
localstack status services

# Restart service
localstack restart
```

### AWS CLI with LocalStack

Configure AWS CLI to use LocalStack:

```bash
# Set endpoint URL
aws --endpoint-url=http://localhost:4566 s3 ls

# Or use aws-local wrapper
pip install awscli-local
awslocal s3 ls
```

### Multiple Environments

Run multiple LocalStack instances:

```yaml
# docker-compose.dev.yml
services:
  localstack-dev:
    ports:
      - "4566:4566"

# docker-compose.test.yml
services:
  localstack-test:
    ports:
      - "4567:4566"  # Different port
```

### Resource Cleanup

Clean up all LocalStack resources:

```bash
# Stop container
make localstack-stop

# Remove container and volumes
make localstack-clean

# Remove all LocalStack data
rm -rf .localstack/data/
```

## Makefile Reference

Complete list of available Make targets:

| Target | Description |
|--------|-------------|
| `make help` | Show all available targets |
| `make localstack-start` | Start LocalStack with health check |
| `make localstack-stop` | Stop LocalStack gracefully |
| `make localstack-restart` | Restart LocalStack |
| `make localstack-status` | Show container status |
| `make localstack-logs` | Tail container logs |
| `make localstack-health` | Check health endpoint |
| `make localstack-clean` | Stop and remove volumes |
| `make test-local` | Run tests with LocalStack |
| `make test-aws` | Run tests with AWS |

## Next Steps

1. **Review test compatibility matrix**: See `docs/localstack-test-matrix.md`
2. **Learn test writing**: See `docs/localstack-testing.md`
3. **Understand provider config**: See `docs/localstack-provider-config.md`
4. **Migrate existing tests**: Follow `docs/localstack-test-migration.md`

## References

- [LocalStack Documentation](https://docs.localstack.cloud/)
- [LocalStack Configuration](https://docs.localstack.cloud/references/configuration/)
- [LocalStack Service Coverage](https://docs.localstack.cloud/user-guide/aws/feature-coverage/)
- [Docker Compose Reference](https://docs.docker.com/compose/)
- [Terraform Testing](https://developer.hashicorp.com/terraform/language/tests)
