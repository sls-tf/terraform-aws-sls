# ============================================================================
# CFN Intrinsic Function Resolution Tests
# ============================================================================
# Tests that !Ref, !Sub, !If, !Equals, Condition: are properly evaluated.
# Requires LocalStack (make localstack-start) or real AWS credentials.

mock_provider "aws" {}

run "intrinsics_sub_resolves_resources" {
  command = plan

  variables {
    config_path           = "tests/fixtures/sam-intrinsics-policies.yaml"
    config_format         = "sam"
    strict_sam_intrinsics = false
    sam_template_parameters = {
      Environment = "dev"
      AppName     = "testapp"
    }
  }

  assert {
    condition     = length(local.validation_errors) == 0
    error_message = "Expected no validation errors, got: ${join(", ", local.validation_errors)}"
  }

  # ApiHandler should have SSM policy with resolved ARNs
  assert {
    condition     = contains(keys(local.parsed_config.functions), "ApiHandlerFunction")
    error_message = "ApiHandlerFunction should exist"
  }

  assert {
    condition = length([
      for stmt in try(local.parsed_config.functions["ApiHandlerFunction"].iamRoleStatements, []) :
      stmt if contains(try(tolist(stmt.Action), []), "ssm:GetParameter")
    ]) > 0
    error_message = "ApiHandlerFunction should have ssm:GetParameter statement"
  }
}

run "intrinsics_if_condition_dev_excludes_prod_policy" {
  command = plan

  variables {
    config_path           = "tests/fixtures/sam-intrinsics-policies.yaml"
    config_format         = "sam"
    strict_sam_intrinsics = false
    sam_template_parameters = {
      Environment = "dev"
      AppName     = "testapp"
    }
  }

  # In dev, IsProd=false so the !If-gated s3:GetObject policy should be absent
  assert {
    condition = length([
      for stmt in try(local.parsed_config.functions["ApiHandlerFunction"].iamRoleStatements, []) :
      stmt if contains(try(tolist(stmt.Action), []), "s3:GetObject")
    ]) == 0
    error_message = "s3:GetObject policy should be absent in dev (IsProd=false)"
  }
}

run "intrinsics_if_condition_prod_includes_prod_policy" {
  command = plan

  variables {
    config_path           = "tests/fixtures/sam-intrinsics-policies.yaml"
    config_format         = "sam"
    strict_sam_intrinsics = false
    sam_template_parameters = {
      Environment = "prod"
      AppName     = "testapp"
    }
  }

  # In prod, IsProd=true so the !If-gated s3:GetObject policy should be present
  assert {
    condition = length([
      for stmt in try(local.parsed_config.functions["ApiHandlerFunction"].iamRoleStatements, []) :
      stmt if contains(try(tolist(stmt.Action), []), "s3:GetObject")
    ]) > 0
    error_message = "s3:GetObject policy should be present in prod (IsProd=true)"
  }
}

run "intrinsics_resource_level_condition_excludes_function" {
  command = plan

  variables {
    config_path           = "tests/fixtures/sam-intrinsics-policies.yaml"
    config_format         = "sam"
    strict_sam_intrinsics = false
    sam_template_parameters = {
      Environment = "dev"
    }
  }

  # ProdOnlyFunction has Condition: IsProd — in dev it should be excluded
  assert {
    condition     = !contains(keys(local.parsed_config.functions), "ProdOnlyFunction")
    error_message = "ProdOnlyFunction should not exist when Environment=dev (IsProd=false)"
  }
}

run "intrinsics_resource_level_condition_includes_function_in_prod" {
  command = plan

  variables {
    config_path           = "tests/fixtures/sam-intrinsics-policies.yaml"
    config_format         = "sam"
    strict_sam_intrinsics = false
    sam_template_parameters = {
      Environment = "prod"
    }
  }

  # ProdOnlyFunction has Condition: IsProd — in prod it should exist
  assert {
    condition     = contains(keys(local.parsed_config.functions), "ProdOnlyFunction")
    error_message = "ProdOnlyFunction should exist when Environment=prod (IsProd=true)"
  }
}

run "intrinsics_worker_has_rds_and_secrets_policies" {
  command = plan

  variables {
    config_path           = "tests/fixtures/sam-intrinsics-policies.yaml"
    config_format         = "sam"
    strict_sam_intrinsics = false
    sam_template_parameters = {
      Environment = "dev"
    }
  }

  assert {
    condition = length([
      for stmt in try(local.parsed_config.functions["WorkerFunction"].iamRoleStatements, []) :
      stmt if contains(try(tolist(stmt.Action), []), "rds-data:ExecuteStatement")
    ]) > 0
    error_message = "WorkerFunction should have rds-data:ExecuteStatement statement"
  }

  assert {
    condition = length([
      for stmt in try(local.parsed_config.functions["WorkerFunction"].iamRoleStatements, []) :
      stmt if contains(try(tolist(stmt.Action), []), "secretsmanager:GetSecretValue")
    ]) > 0
    error_message = "WorkerFunction should have secretsmanager:GetSecretValue statement"
  }
}

run "intrinsics_sub_2arg_resolves" {
  command = plan

  variables {
    config_path           = "tests/fixtures/sam-sub-2arg.yaml"
    config_format         = "sam"
    strict_sam_intrinsics = false
    sam_template_parameters = {
      Env = "staging"
    }
  }

  assert {
    condition     = length(local.validation_errors) == 0
    error_message = "Expected no validation errors for 2-arg Sub fixture: ${join(", ", local.validation_errors)}"
  }

  assert {
    condition = length([
      for stmt in try(local.parsed_config.functions["MyFunction"].iamRoleStatements, []) :
      stmt if contains(try(tolist(stmt.Action), []), "ssm:GetParameter")
    ]) > 0
    error_message = "MyFunction should have ssm:GetParameter statement after 2-arg Sub resolution"
  }
}
