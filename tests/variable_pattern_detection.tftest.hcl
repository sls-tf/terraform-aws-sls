# Variable Pattern Detection Tests
# Tests for extracting and parsing variable patterns from configs

mock_provider "aws" {}

run "test_detect_self_variables" {
  command = plan

  variables {
    config_path = "tests/fixtures/variables-self-reference.yml"
  }

  # Should detect ${self:} variables in the config
  assert {
    condition     = length(local.extract_variable_refs) > 0
    error_message = "Should detect variable references in config"
  }
}

run "test_detect_env_variables" {
  command = plan

  variables {
    config_path = "tests/fixtures/variables-env.yml"
    environment_vars = {
      "STAGE"      = "production"
      "AWS_REGION" = "us-west-2"
      "NODE_ENV"   = "production"
    }
  }

  # Should detect ${env:} variables
  assert {
    condition     = length(local.extract_variable_refs) > 0
    error_message = "Should detect environment variable references"
  }
}

run "test_no_variables_in_simple_config" {
  command = plan

  variables {
    config_path = "tests/fixtures/simple-function.yml"
  }

  # Should not detect variables in config without any
  assert {
    condition     = length(local.extract_variable_refs) == 0
    error_message = "Should not detect variables in simple config"
  }
}

run "test_variable_pattern_regex" {
  command = plan

  variables {
    config_path = "tests/fixtures/simple-function.yml"
  }

  # Should have valid regex pattern
  assert {
    condition     = local.variable_pattern_regex == "\\$\\{([^}]+)\\}"
    error_message = "Variable pattern regex should match $${...} syntax"
  }
}

run "test_parsed_variables_structure" {
  command = plan

  variables {
    config_path = "tests/fixtures/variables-self-reference.yml"
  }

  # Should parse variables into structured format
  assert {
    condition     = can(local.parsed_variables)
    error_message = "Should be able to parse variables into structured format"
  }
}
