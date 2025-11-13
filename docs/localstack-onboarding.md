# LocalStack Developer Onboarding

Quick start guide for developers joining the project and using LocalStack for testing.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start (5 Minutes)](#quick-start-5-minutes)
- [Understanding the Setup](#understanding-the-setup)
- [Daily Workflow](#daily-workflow)
- [Writing Tests](#writing-tests)
- [Troubleshooting](#troubleshooting)
- [Resources](#resources)

## Overview

This project uses **LocalStack** for local AWS testing. LocalStack provides a local AWS cloud stack that lets you:

- ✅ Test AWS resources locally without AWS credentials
- ✅ Run tests in seconds instead of minutes
- ✅ Develop offline without internet connectivity
- ✅ Avoid AWS costs during development
- ✅ Ensure consistent test environments

**What You'll Learn:**
- How to start LocalStack (< 1 minute)
- How to run tests locally (< 1 minute)
- How to write LocalStack-compatible tests (10 minutes)
- Where to get help (< 1 minute)

## Prerequisites

### Required Software

Install these before starting:

1. **Docker** (20.10 or later)
   - Mac: [Docker Desktop for Mac](https://docs.docker.com/desktop/install/mac-install/)
   - Windows: [Docker Desktop for Windows](https://docs.docker.com/desktop/install/windows-install/)
   - Linux: [Docker Engine](https://docs.docker.com/engine/install/)

   Verify:
   ```bash
   docker --version
   # Should output: Docker version 20.10.x or higher
   ```

2. **Docker Compose** (2.0 or later)
   - Included with Docker Desktop
   - Linux: `sudo apt-get install docker-compose-plugin`

   Verify:
   ```bash
   docker-compose --version
   # Should output: Docker Compose version 2.x.x or higher
   ```

3. **Terraform** (1.5 or later)
   - [Download Terraform](https://www.terraform.io/downloads)

   Verify:
   ```bash
   terraform --version
   # Should output: Terraform v1.5.x or higher
   ```

4. **Make** (optional, but recommended)
   - Mac: `xcode-select --install`
   - Linux: `sudo apt-get install build-essential`
   - Windows: [Make for Windows](http://gnuwin32.sourceforge.net/packages/make.htm) or use WSL

   Verify:
   ```bash
   make --version
   # Should output: GNU Make 3.81 or higher
   ```

### Verify Installation

Run this quick check:

```bash
# Clone the repository (if not already done)
git clone <repository-url>
cd sls.tf

# Check all prerequisites
docker --version && \
docker-compose --version && \
terraform --version && \
make --version && \
echo "✅ All prerequisites installed!"
```

## Quick Start (5 Minutes)

Get up and running with LocalStack in 5 minutes:

### Step 1: Start LocalStack (1 minute)

```bash
# Start LocalStack container
make localstack-start
```

**Expected output:**
```
Starting LocalStack...
Creating sls-tf-localstack ... done
Waiting for LocalStack to be healthy...
✓ LocalStack is ready!
```

**What this does:**
- Starts LocalStack Docker container
- Waits for health check to pass
- Loads AWS services (Lambda, API Gateway, S3, etc.)

### Step 2: Verify LocalStack is Running (30 seconds)

```bash
# Check health status
make localstack-health
```

**Expected output:**
```json
{
  "services": {
    "lambda": "running",
    "apigateway": "running",
    "s3": "running",
    "iam": "running",
    "dynamodb": "running",
    "sqs": "running",
    "sns": "running",
    "events": "running",
    "route53": "running"
  }
}
```

### Step 3: Run Tests (2 minutes)

```bash
# Initialize Terraform (first time only)
terraform init

# Run tests with LocalStack
make test-local
```

**Expected output:**
```
Success! 16 passed, 0 failed.
```

### Step 4: Celebrate! 🎉

You're now running AWS tests locally without any AWS credentials or costs!

**Optional:** Stop LocalStack when done:
```bash
make localstack-stop
```

## Understanding the Setup

### What Just Happened?

1. **Docker Compose** started a LocalStack container
2. **LocalStack** emulates AWS services on `localhost:4566`
3. **Terraform** connected to LocalStack instead of AWS
4. **Tests** ran against local resources, not real AWS

### Architecture

```
┌─────────────────────────────────────────┐
│  Your Machine                            │
│                                          │
│  ┌──────────────┐                       │
│  │   Terraform   │                       │
│  │    Tests      │                       │
│  └───────┬───────┘                       │
│          │                               │
│          │ HTTP requests to              │
│          │ localhost:4566                │
│          ↓                               │
│  ┌──────────────────────────────┐       │
│  │  LocalStack Container         │       │
│  │                               │       │
│  │  ┌────────┐  ┌──────────┐   │       │
│  │  │ Lambda │  │    S3     │   │       │
│  │  └────────┘  └──────────┘   │       │
│  │  ┌────────┐  ┌──────────┐   │       │
│  │  │   API  │  │   IAM     │   │       │
│  │  │Gateway │  │           │   │       │
│  │  └────────┘  └──────────┘   │       │
│  └──────────────────────────────┘       │
└─────────────────────────────────────────┘
```

### Key Files

| File | Purpose |
|------|---------|
| `docker-compose.localstack.yml` | LocalStack container config |
| `Makefile` | Convenience commands |
| `variables.tf` | LocalStack variables |
| `tests/*.tftest.hcl` | Test files |

### Key Commands

| Command | Purpose |
|---------|---------|
| `make localstack-start` | Start LocalStack |
| `make localstack-stop` | Stop LocalStack |
| `make localstack-status` | Check if running |
| `make localstack-logs` | View container logs |
| `make test-local` | Run tests with LocalStack |
| `make test-aws` | Run tests with AWS |

## Daily Workflow

### Morning Routine

Start your day with LocalStack:

```bash
# 1. Pull latest changes
git pull

# 2. Start LocalStack
make localstack-start

# 3. Run tests to verify everything works
make test-local
```

**Time:** ~2 minutes

### Development Cycle

When working on features or fixes:

```bash
# 1. Make code changes
# (edit Terraform files)

# 2. Run tests
make test-local

# 3. Fix issues if needed
# (iterate)

# 4. Run specific test during debugging
terraform test -filter="tests/your_test.tftest.hcl" -var="use_localstack=true"

# 5. When ready, test with AWS (if credentials available)
make test-aws
```

### End of Day

Clean up before signing off:

```bash
# Stop LocalStack (saves resources)
make localstack-stop

# Or completely clean up
make localstack-clean
```

### Weekly Maintenance

Once a week, update LocalStack:

```bash
# Stop LocalStack
make localstack-stop

# Pull latest image
docker pull localstack/localstack:latest

# Restart
make localstack-start
```

## Writing Tests

### Adding LocalStack Support to Existing Tests

If you're migrating an existing test to support LocalStack:

**Step 1:** Add compatibility header

```hcl
# My Test Name
# LocalStack Compatibility: FULL
# Brief description of what this test validates
```

**Step 2:** Add provider configuration

```hcl
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
```

**Step 3:** Test it

```bash
terraform test -filter="tests/your_test.tftest.hcl" -var="use_localstack=true"
```

**Step 4:** Adjust assertions if needed

If tests fail due to URL or ARN format differences, see [Test Migration Guide](./localstack-test-migration.md).

### Writing New Tests

For new tests, use the template:

```bash
# Copy template
cp tests/test_provider_template.txt tests/new_test.tftest.hcl

# Edit with your test logic
vim tests/new_test.tftest.hcl
```

Template structure:

```hcl
# Test Name
# LocalStack Compatibility: FULL
# Description

provider "aws" {
  # ... provider config from template
}

run "test_scenario_1" {
  command = plan

  variables {
    # Test inputs
  }

  assert {
    condition     = # Your condition
    error_message = "Error message"
  }
}
```

### Test Writing Tips

1. **Start with parsing tests** - Easiest to write, no AWS resources
2. **Use FULL compatibility** - Most tests should work fully with LocalStack
3. **Test locally first** - Faster feedback than AWS
4. **Document limitations** - Note any LocalStack-specific behavior
5. **Keep tests focused** - One concern per test

### Common Patterns

**URL validation (dual-mode):**
```hcl
assert {
  condition = var.use_localstack ? (
    can(regex("localhost:4566", resource.url))
  ) : (
    can(regex("amazonaws\\.com", resource.url))
  )
  error_message = "Invalid URL"
}
```

**ARN validation (flexible):**
```hcl
assert {
  condition = can(regex("^arn:(aws|localstack):", resource.arn))
  error_message = "Invalid ARN"
}
```

**Skip AWS-specific checks:**
```hcl
assert {
  condition = var.use_localstack || (
    # AWS-only validation
    resource.attribute == "expected"
  )
  error_message = "Validation failed"
}
```

## Troubleshooting

### Quick Fixes

| Problem | Solution |
|---------|----------|
| LocalStack won't start | `make localstack-clean && make localstack-start` |
| Tests fail with connection errors | Check `make localstack-status` |
| Port 4566 already in use | `lsof -i :4566` and kill process |
| Tests are slow | Check `docker stats sls-tf-localstack` |
| Out of disk space | `docker system prune -f` |

### Debug Commands

```bash
# Check LocalStack is running
docker ps | grep localstack

# View recent logs
make localstack-logs

# Check health endpoint
curl http://localhost:4566/_localstack/health | jq

# Run test with debug output
TF_LOG=DEBUG terraform test -filter="tests/your_test.tftest.hcl" -var="use_localstack=true"

# Check which port LocalStack is using
docker port sls-tf-localstack
```

### Common Issues

#### Issue: "Docker daemon not running"

**Solution:**
```bash
# Mac/Windows: Start Docker Desktop application
# Linux:
sudo systemctl start docker
```

#### Issue: "Health check timeout"

**Solution:**
```bash
# Check logs for errors
make localstack-logs

# Try restarting
make localstack-restart
```

#### Issue: "Tests pass in AWS but fail in LocalStack"

**Solution:**
See [Test Migration Guide](./localstack-test-migration.md) for assertion adjustment patterns.

#### Issue: "S3 operations fail"

**Solution:**
Verify provider has `s3_use_path_style = var.use_localstack`

### Getting Help

1. **Check documentation:**
   - [LocalStack Setup Guide](./localstack-setup.md)
   - [Test Migration Guide](./localstack-test-migration.md)
   - [Troubleshooting Guide](./localstack-troubleshooting.md)

2. **Run diagnostics:**
   ```bash
   make localstack-status
   make localstack-logs
   ```

3. **Ask the team:**
   - Check existing GitHub issues
   - Ask in team chat
   - Create new issue with logs

4. **LocalStack community:**
   - [GitHub Discussions](https://github.com/localstack/localstack/discussions)
   - [Slack](https://localstack.cloud/slack)

## Resources

### Documentation

| Document | Purpose | When to Read |
|----------|---------|--------------|
| [LocalStack Setup](./localstack-setup.md) | Detailed setup and configuration | Installation issues |
| [Testing Guide](./localstack-testing.md) | Comprehensive testing patterns | Writing tests |
| [Test Migration](./localstack-test-migration.md) | Migrating existing tests | Converting old tests |
| [Troubleshooting](./localstack-troubleshooting.md) | Detailed problem solving | When stuck |
| [Variables](./localstack-variables.md) | Variable reference | Configuration issues |
| [Provider Config](./localstack-provider-config.md) | Provider setup details | Provider errors |

### External Resources

- [LocalStack Docs](https://docs.localstack.cloud/)
- [Terraform Testing](https://developer.hashicorp.com/terraform/language/tests)
- [Docker Compose](https://docs.docker.com/compose/)

### Cheat Sheet

Print this for quick reference:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          LOCALSTACK CHEAT SHEET
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

START/STOP:
  make localstack-start    Start LocalStack
  make localstack-stop     Stop LocalStack
  make localstack-restart  Restart LocalStack
  make localstack-clean    Remove completely

STATUS:
  make localstack-status   Check if running
  make localstack-health   Check health endpoint
  make localstack-logs     View logs

TESTING:
  make test-local         Run tests with LocalStack
  make test-aws          Run tests with AWS
  terraform test \       Run specific test
    -filter="tests/foo.tftest.hcl" \
    -var="use_localstack=true"

DEBUG:
  docker ps              List containers
  docker logs <id>       View container logs
  curl localhost:4566/_localstack/health

TROUBLESHOOTING:
  1. make localstack-status
  2. make localstack-logs
  3. make localstack-restart
  4. Check docs/localstack-troubleshooting.md

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Next Steps

### Beginner Tasks (Week 1)

- [ ] Install all prerequisites
- [ ] Start LocalStack successfully
- [ ] Run test suite with LocalStack
- [ ] Read through one test file to understand structure
- [ ] Run a single test file
- [ ] View LocalStack logs

### Intermediate Tasks (Week 2)

- [ ] Add LocalStack support to an existing simple test
- [ ] Write a new parsing test
- [ ] Write a new resource creation test
- [ ] Debug a failing test
- [ ] Use conditional assertions in a test

### Advanced Tasks (Week 3+)

- [ ] Migrate a complex integration test
- [ ] Write tests for a new module feature
- [ ] Optimize test performance
- [ ] Contribute to test documentation
- [ ] Help onboard another developer

## Onboarding Checklist

Use this checklist for your first week:

### Day 1: Setup
- [ ] Install Docker, Docker Compose, Terraform, Make
- [ ] Clone repository
- [ ] Start LocalStack
- [ ] Run test suite successfully
- [ ] Stop LocalStack

### Day 2: Exploration
- [ ] Read LocalStack setup guide
- [ ] Explore test file structure
- [ ] Run individual test files
- [ ] View LocalStack logs
- [ ] Check LocalStack health endpoint

### Day 3: Understanding
- [ ] Read test migration guide
- [ ] Understand provider configuration
- [ ] Review variable usage
- [ ] Identify different test types (parsing, resource, integration)
- [ ] Understand compatibility levels

### Day 4: Practice
- [ ] Add LocalStack support to a simple test
- [ ] Test with both LocalStack and AWS (if credentials available)
- [ ] Debug a test failure
- [ ] Use debug logging

### Day 5: Independence
- [ ] Write a new test from scratch
- [ ] Successfully migrate a test without help
- [ ] Help another developer with LocalStack
- [ ] Identify and document a limitation
- [ ] Suggest an improvement

## Feedback

This onboarding guide is a living document. If you:

- Found something confusing
- Encountered an issue not covered here
- Have suggestions for improvement
- Want to add helpful tips

Please open an issue or submit a PR!

## Welcome Aboard! 🚀

You're now ready to use LocalStack for fast, local AWS testing. Remember:

- **Start LocalStack before testing**: `make localstack-start`
- **Run tests locally first**: `make test-local`
- **Check docs when stuck**: `docs/localstack-*.md`
- **Ask for help**: Team is here to help!

Happy testing! 🎉
