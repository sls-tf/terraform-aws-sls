# ${self:} Variable Resolution Tests
# Tests for resolving ${self:} references to config properties

run "test_resolve_self_service" {
  command = plan

  variables {
    config_path = "tests/fixtures/variables-self-reference.yml"
  }

  # Should resolve ${self:service} to actual service name
  assert {
    condition     = local.traverse_path["service"] == "test-variables"
    error_message = "Should resolve service name"
  }
}

run "test_resolve_self_provider_stage" {
  command = plan

  variables {
    config_path = "tests/fixtures/variables-self-reference.yml"
  }

  # ${self:provider.stage} should initially be ${self:custom.defaultStage}
  # After resolution, should be "dev"
  assert {
    condition     = local.traverse_path["custom.defaultStage"] == "dev"
    error_message = "Should resolve custom.defaultStage to 'dev'"
  }
}

run "test_config_with_self_resolved" {
  command = plan

  variables {
    config_path = "tests/fixtures/variables-self-reference.yml"
  }

  # Should have config_with_self_resolved local
  assert {
    condition     = can(local.config_with_self_resolved)
    error_message = "Should create config_with_self_resolved"
  }
}

run "test_traverse_path_handles_missing" {
  command = plan

  variables {
    config_path = "tests/fixtures/valid-minimal.yml"
  }

  # Should handle missing paths gracefully (return null)
  assert {
    condition     = local.traverse_path["custom.defaultStage"] == null
    error_message = "Should return null for missing paths"
  }
}

run "test_resolved_config_exists" {
  command = plan

  variables {
    config_path = "tests/fixtures/variables-self-reference.yml"
  }

  # Should create resolved_config
  assert {
    condition     = can(local.resolved_config)
    error_message = "Should create resolved_config"
  }

  # resolved_config should have service name
  assert {
    condition     = local.resolved_config.service == "test-variables"
    error_message = "resolved_config should preserve service name"
  }
}
