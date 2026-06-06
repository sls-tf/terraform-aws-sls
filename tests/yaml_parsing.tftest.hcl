# YAML Parsing Tests
# These tests verify YAML parsing functionality with various configurations

# Configure required providers for tests
mock_provider "aws" {}

provider "null" {}

# Test 1: Valid YAML parsing with minimal serverless.yml
run "valid_minimal_yaml" {
  command = plan

  variables {
    config_path = "tests/fixtures/valid-minimal.yml"
  }

  assert {
    condition     = local.parsed_config != null
    error_message = "Failed to parse valid minimal YAML configuration"
  }

  assert {
    condition     = local.parsed_config.service != null
    error_message = "Service field not found in parsed configuration"
  }
}

# Test 2: Invalid YAML syntax error handling
run "invalid_yaml_syntax" {
  command = plan

  variables {
    config_path = "tests/fixtures/invalid-syntax.yml"
  }

  expect_failures = [
    null_resource.config_validation
  ]
}

# Test 3: File not found error handling
run "file_not_found" {
  command = plan

  variables {
    config_path = "tests/fixtures/nonexistent.yml"
  }

  expect_failures = [
    null_resource.config_validation
  ]
}

# Test 4: Empty file handling
run "empty_file" {
  command = plan

  variables {
    config_path = "tests/fixtures/empty.yml"
  }

  expect_failures = [
    null_resource.config_validation
  ]
}

# Test 5: Valid YAML with full configuration
run "valid_full_yaml" {
  command = plan

  variables {
    config_path = "tests/fixtures/valid-full.yml"
  }

  assert {
    condition     = local.parsed_config != null
    error_message = "Failed to parse valid full YAML configuration"
  }

  assert {
    condition     = local.parsed_config.provider != null
    error_message = "Provider field not found in parsed configuration"
  }

  assert {
    condition     = local.parsed_config.functions != null
    error_message = "Functions field not found in parsed configuration"
  }
}
