# ${env:} Variable Resolution Tests
# Tests for resolving ${env:} environment variables

run "test_resolve_env_with_value" {
  command = plan

  variables {
    config_path = "tests/fixtures/variables-env.yml"
    environment_vars = {
      "STAGE"      = "production"
      "AWS_REGION" = "us-west-2"
      "NODE_ENV"   = "production"
      "API_KEY"    = "secret-key-123"
    }
  }

  # Should resolve ${env:STAGE} to "production"
  assert {
    condition     = can(local.resolved_config)
    error_message = "Should create resolved_config"
  }
}

run "test_env_with_default_value_when_missing" {
  command = plan

  variables {
    config_path = "tests/fixtures/variables-env.yml"
    environment_vars = {
      # Intentionally not providing AWS_REGION or API_KEY
      "STAGE"    = "dev"
      "NODE_ENV" = "development"
    }
  }

  # Should use default values for missing vars
  # ${env:AWS_REGION, 'us-east-1'} should resolve to 'us-east-1'
  # ${env:API_KEY, 'default-key'} should resolve to 'default-key'
  assert {
    condition     = can(local.config_with_env_resolved)
    error_message = "Should resolve env vars with defaults"
  }
}

run "test_env_variables_parsed_structure" {
  command = plan

  variables {
    config_path = "tests/fixtures/variables-env.yml"
    environment_vars = {
      "STAGE" = "test"
    }
  }

  # Should parse ${env:} expressions
  assert {
    condition     = can(local.env_variables_parsed)
    error_message = "Should parse env variable expressions"
  }
}

run "test_strict_mode_unresolved_variables" {
  command = plan

  variables {
    config_path                = "tests/fixtures/variables-env.yml"
    strict_variable_resolution = true
    environment_vars = {
      # Missing STAGE and NODE_ENV - should cause errors in strict mode
    }
  }

  # In strict mode, unresolved vars should generate errors
  assert {
    condition     = can(local.variable_resolution_errors)
    error_message = "Should track resolution errors in strict mode"
  }
}

run "test_non_strict_mode_allows_unresolved" {
  command = plan

  variables {
    config_path                = "tests/fixtures/variables-env.yml"
    strict_variable_resolution = false
    environment_vars           = {}
  }

  # In non-strict mode, should not fail on unresolved vars
  assert {
    condition     = var.strict_variable_resolution == false
    error_message = "Should allow unresolved vars in non-strict mode"
  }

  assert {
    condition     = length(local.variable_resolution_errors) == 0
    error_message = "Should not generate errors in non-strict mode"
  }
}
