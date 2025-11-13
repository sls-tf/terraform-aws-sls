# Gap Coverage Tests
# Strategic tests to fill critical coverage gaps identified in Task 6.2

provider "null" {}

# Test 1: Framework version 2.x validation
run "framework_version_2x" {
  command = plan

  variables {
    config_path = "tests/fixtures/framework-2x.yml"
  }

  assert {
    condition     = length(local.validation_errors) == 0
    error_message = "Framework version 2.x should be valid"
  }
}

# Test 2: Framework version 4.x validation
run "framework_version_4x" {
  command = plan

  variables {
    config_path = "tests/fixtures/framework-4x.yml"
  }

  assert {
    condition     = length(local.validation_errors) == 0
    error_message = "Framework version 4.x should be valid"
  }
}

# Test 3: Invalid framework version rejection
run "framework_version_invalid" {
  command = plan

  variables {
    config_path = "tests/fixtures/framework-invalid.yml"
  }

  expect_failures = [
    null_resource.config_validation
  ]
}

# Test 4: Provider runtime inheritance to all functions
run "provider_runtime_inheritance_all" {
  command = plan

  variables {
    config_path = "tests/fixtures/runtime-inheritance-all.yml"
  }

  assert {
    condition     = local.functions_with_defaults["func1"].runtime == "nodejs18.x"
    error_message = "Function 1 should inherit provider runtime"
  }

  assert {
    condition     = local.functions_with_defaults["func2"].runtime == "nodejs18.x"
    error_message = "Function 2 should inherit provider runtime"
  }

  assert {
    condition     = local.functions_with_defaults["func3"].runtime == "nodejs18.x"
    error_message = "Function 3 should inherit provider runtime"
  }
}

# Test 5: Memory boundary values (min: 128)
run "memory_boundary_min" {
  command = plan

  variables {
    config_path = "tests/fixtures/memory-boundary-min.yml"
  }

  assert {
    condition     = local.provider_with_defaults.memorySize == 128
    error_message = "Minimum memorySize 128 should be valid"
  }
}

# Test 6: Memory boundary values (max: 10240)
run "memory_boundary_max" {
  command = plan

  variables {
    config_path = "tests/fixtures/memory-boundary-max.yml"
  }

  assert {
    condition     = local.provider_with_defaults.memorySize == 10240
    error_message = "Maximum memorySize 10240 should be valid"
  }
}

# Test 7: Timeout boundary values (min: 1)
run "timeout_boundary_min" {
  command = plan

  variables {
    config_path = "tests/fixtures/timeout-boundary-min.yml"
  }

  assert {
    condition     = local.provider_with_defaults.timeout == 1
    error_message = "Minimum timeout 1 should be valid"
  }
}

# Test 8: Timeout boundary values (max: 900)
run "timeout_boundary_max" {
  command = plan

  variables {
    config_path = "tests/fixtures/timeout-boundary-max.yml"
  }

  assert {
    condition     = local.provider_with_defaults.timeout == 900
    error_message = "Maximum timeout 900 should be valid"
  }
}

# Test 9: Complex function configuration with mixed defaults/overrides
run "complex_function_mixed" {
  command = plan

  variables {
    config_path = "tests/fixtures/complex-mixed.yml"
  }

  assert {
    condition = (
      local.functions_with_defaults["inherits_all"].runtime == "nodejs18.x" &&
      local.functions_with_defaults["inherits_all"].memorySize == 512 &&
      local.functions_with_defaults["inherits_all"].timeout == 10
    )
    error_message = "Function with no overrides should inherit all provider defaults"
  }

  assert {
    condition = (
      local.functions_with_defaults["overrides_runtime"].runtime == "python3.9" &&
      local.functions_with_defaults["overrides_runtime"].memorySize == 512 &&
      local.functions_with_defaults["overrides_runtime"].timeout == 10
    )
    error_message = "Function should override runtime but inherit memory and timeout"
  }

  assert {
    condition = (
      local.functions_with_defaults["overrides_all"].runtime == "python3.11" &&
      local.functions_with_defaults["overrides_all"].memorySize == 2048 &&
      local.functions_with_defaults["overrides_all"].timeout == 60
    )
    error_message = "Function should override all properties"
  }
}

# Test 10: Complete valid configuration end-to-end
run "complete_valid_config_e2e" {
  command = plan

  variables {
    config_path = "tests/fixtures/complete-valid.yml"
  }

  assert {
    condition     = local.parsed_config != null
    error_message = "Parsed config should not be null"
  }

  assert {
    condition     = length(local.validation_errors) == 0
    error_message = "Complete valid config should have no validation errors"
  }

  assert {
    condition     = local.parsed_config.service == "complete-service"
    error_message = "Service name should be extracted"
  }

  assert {
    condition     = local.provider_with_defaults != null
    error_message = "Provider config with defaults should be populated"
  }

  assert {
    condition     = length(local.functions_with_defaults) > 0
    error_message = "Functions with defaults should be populated"
  }

  assert {
    condition     = local.parsed_config.custom != null
    error_message = "Custom section should be accessible"
  }

  assert {
    condition     = local.parsed_config.resources != null
    error_message = "Resources section should be accessible"
  }

  assert {
    condition     = local.parsed_config.package != null
    error_message = "Package section should be accessible"
  }
}
