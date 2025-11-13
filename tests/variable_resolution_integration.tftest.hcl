# Variable Resolution Integration Tests
# End-to-end tests verifying variable resolution works with the full module

run "test_self_variables_in_complete_config" {
  command = plan

  variables {
    config_path = "tests/fixtures/variables-self-reference.yml"
  }

  # Should successfully parse and resolve ${self:} variables
  assert {
    condition     = local.parsed_config != null
    error_message = "Should parse config successfully"
  }

  assert {
    condition     = local.resolved_config != null
    error_message = "Should create resolved config"
  }

  # The resolved config should be accessible
  assert {
    condition     = local.parsed_config_resolved != null
    error_message = "Should create parsed_config_resolved alias"
  }

  # Service name should be preserved
  assert {
    condition     = local.resolved_config.service == "test-variables"
    error_message = "Resolved config should preserve service name"
  }
}

run "test_env_variables_in_complete_config" {
  command = plan

  variables {
    config_path = "tests/fixtures/variables-env.yml"
    environment_vars = {
      "STAGE"      = "production"
      "AWS_REGION" = "us-west-2"
      "NODE_ENV"   = "production"
      "API_KEY"    = "prod-key-456"
    }
  }

  # Should resolve all ${env:} variables
  assert {
    condition     = local.resolved_config != null
    error_message = "Should create resolved config with env vars"
  }

  # Should not have resolution errors in strict mode when all vars provided
  assert {
    condition     = length(local.variable_resolution_errors) == 0
    error_message = "Should not have resolution errors when all env vars provided"
  }
}

run "test_mixed_self_and_env_variables" {
  command = plan

  variables {
    config_path = "tests/fixtures/variables-self-reference.yml"
    environment_vars = {
      "STAGE" = "staging"
    }
  }

  # Should handle config with only ${self:} variables (no ${env:})
  assert {
    condition     = local.resolved_config != null
    error_message = "Should handle mixed variable types"
  }
}

run "test_no_variables_backward_compatibility" {
  command = plan

  variables {
    config_path = "tests/fixtures/simple-function.yml"
  }

  # Should work normally for configs without variables
  assert {
    condition     = local.resolved_config != null
    error_message = "Should handle configs without variables"
  }

  # parsed_config and resolved_config should be equivalent for configs without variables
  assert {
    condition     = local.parsed_config.service == local.resolved_config.service
    error_message = "Configs without variables should remain unchanged"
  }
}

run "test_variable_resolution_with_validation" {
  command = plan

  variables {
    config_path = "tests/fixtures/variables-self-reference.yml"
  }

  # Module validation should still work with resolved config
  assert {
    condition     = can(local.validation_errors)
    error_message = "Validation should work with variable resolution"
  }

  # Should not have validation errors for valid config
  assert {
    condition     = length([for err in local.validation_errors : err if err != ""]) == 0
    error_message = "Valid config should pass validation after resolution"
  }
}
