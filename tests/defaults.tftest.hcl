# Default Application Tests
# LocalStack Compatibility: FULL
# These tests verify default value application and inheritance
# These are parsing tests that validate default values in locals

provider "aws" {
  region = "us-east-1"

  # Skip AWS-specific validations when using LocalStack
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack

  # CRITICAL: LocalStack requires S3 path-style access
  s3_use_path_style = var.use_localstack

  # Dynamic endpoints - only populated when use_localstack = true
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

provider "null" {}

# Test 1: Stage defaults to "dev"
run "stage_defaults_to_dev" {
  command = plan

  variables {
    config_path = "tests/fixtures/no-stage.yml"
  }

  assert {
    condition     = local.provider_with_defaults.stage == "dev"
    error_message = "Stage should default to 'dev'"
  }
}

# Test 2: Region defaults to "us-east-1"
run "region_defaults_to_us_east_1" {
  command = plan

  variables {
    config_path = "tests/fixtures/no-region.yml"
  }

  assert {
    condition     = local.provider_with_defaults.region == "us-east-1"
    error_message = "Region should default to 'us-east-1'"
  }
}

# Test 3: MemorySize defaults to 1024
run "memory_defaults_to_1024" {
  command = plan

  variables {
    config_path = "tests/fixtures/no-memory.yml"
  }

  assert {
    condition     = local.provider_with_defaults.memorySize == 1024
    error_message = "MemorySize should default to 1024"
  }
}

# Test 4: Timeout defaults to 6
run "timeout_defaults_to_6" {
  command = plan

  variables {
    config_path = "tests/fixtures/no-timeout.yml"
  }

  assert {
    condition     = local.provider_with_defaults.timeout == 6
    error_message = "Timeout should default to 6"
  }
}

# Test 5: Runtime has NO default (strict validation)
run "runtime_no_default" {
  command = plan

  variables {
    config_path = "tests/fixtures/valid-minimal.yml"
  }

  assert {
    condition     = local.provider_with_defaults.runtime == "nodejs18.x"
    error_message = "Runtime should be preserved from config, not defaulted"
  }
}

# Test 6: Function inherits provider defaults
run "function_inherits_defaults" {
  command = plan

  variables {
    config_path = "tests/fixtures/function-inheritance.yml"
  }

  assert {
    condition     = local.functions_with_defaults["hello"].runtime == "nodejs18.x"
    error_message = "Function should inherit runtime from provider"
  }

  assert {
    condition     = local.functions_with_defaults["hello"].memorySize == 512
    error_message = "Function should inherit memorySize from provider"
  }
}

# Test 7: Function overrides take precedence
run "function_overrides_precedence" {
  command = plan

  variables {
    config_path = "tests/fixtures/function-overrides.yml"
  }

  assert {
    condition     = local.functions_with_defaults["custom"].runtime == "python3.9"
    error_message = "Function override runtime should take precedence"
  }

  assert {
    condition     = local.functions_with_defaults["custom"].memorySize == 2048
    error_message = "Function override memorySize should take precedence"
  }
}
