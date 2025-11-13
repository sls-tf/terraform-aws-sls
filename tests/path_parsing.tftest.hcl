# Path Parsing and Resource Tree Building Tests
# LocalStack Compatibility: FULL
# Tests for parsing HTTP paths and building API Gateway resource hierarchy
# These are parsing tests that validate locals - no AWS resources are created

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

run "simple_path_parsing" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-short-form.yml"
  }

  assert {
    condition     = length(local.all_paths) == 1
    error_message = "Should extract one unique path"
  }

  assert {
    condition     = contains(local.all_paths, "/users/{id}")
    error_message = "Should extract /users/{id} path"
  }

  assert {
    condition     = length(local.path_segments["/users/{id}"]) == 2
    error_message = "Path /users/{id} should have 2 segments"
  }

  assert {
    condition     = local.path_segments["/users/{id}"][0] == "users"
    error_message = "First segment should be 'users'"
  }

  assert {
    condition     = local.path_segments["/users/{id}"][1] == "{id}"
    error_message = "Second segment should be '{id}'"
  }
}

run "nested_path_parsing" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-nested-paths.yml"
  }

  assert {
    condition     = length(local.all_paths) == 1
    error_message = "Should extract one unique path"
  }

  assert {
    condition     = contains(local.all_paths, "/users/{id}/posts/{postId}")
    error_message = "Should extract nested path"
  }

  assert {
    condition     = length(local.path_segments["/users/{id}/posts/{postId}"]) == 4
    error_message = "Nested path should have 4 segments"
  }
}

run "intermediate_path_generation" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-nested-paths.yml"
  }

  assert {
    condition     = length(local.all_resource_paths) == 4
    error_message = "Should generate 4 intermediate paths for nested route, got: ${length(local.all_resource_paths)}"
  }

  assert {
    condition     = contains(local.all_resource_paths, "/users")
    error_message = "Should include /users intermediate path"
  }

  assert {
    condition     = contains(local.all_resource_paths, "/users/{id}")
    error_message = "Should include /users/{id} intermediate path"
  }

  assert {
    condition     = contains(local.all_resource_paths, "/users/{id}/posts")
    error_message = "Should include /users/{id}/posts intermediate path"
  }

  assert {
    condition     = contains(local.all_resource_paths, "/users/{id}/posts/{postId}")
    error_message = "Should include full path /users/{id}/posts/{postId}"
  }
}

run "resource_tree_structure" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-nested-paths.yml"
  }

  assert {
    condition     = local.resource_tree["/users"].depth == 1
    error_message = "/users should have depth 1"
  }

  assert {
    condition     = local.resource_tree["/users"].path_part == "users"
    error_message = "/users path_part should be 'users'"
  }

  assert {
    condition     = local.resource_tree["/users"].parent_path == null
    error_message = "/users should have no parent (root level)"
  }

  assert {
    condition     = local.resource_tree["/users/{id}"].depth == 2
    error_message = "/users/{id} should have depth 2"
  }

  assert {
    condition     = local.resource_tree["/users/{id}"].path_part == "{id}"
    error_message = "/users/{id} path_part should be '{id}'"
  }

  assert {
    condition     = local.resource_tree["/users/{id}"].parent_path == "/users"
    error_message = "/users/{id} parent should be /users"
  }

  assert {
    condition     = local.resource_tree["/users/{id}/posts"].parent_path == "/users/{id}"
    error_message = "/users/{id}/posts parent should be /users/{id}"
  }
}

run "resource_name_sanitization" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-nested-paths.yml"
  }

  assert {
    condition     = local.resource_tree["/users"].resource_name == "_users"
    error_message = "Resource name should replace leading / with _"
  }

  assert {
    condition     = local.resource_tree["/users/{id}"].resource_name == "_users_id"
    error_message = "Resource name should strip {} but keep underscores, got: ${local.resource_tree["/users/{id}"].resource_name}"
  }

  assert {
    condition     = local.resource_tree["/users/{id}/posts/{postId}"].resource_name == "_users_id_posts_postId"
    error_message = "Resource name should be sanitized for Terraform, got: ${local.resource_tree["/users/{id}/posts/{postId}"].resource_name}"
  }
}
