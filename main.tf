data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Package Lambda function code (local mode only — skipped when
# var.lambda_code_source.type == "s3", in which case each function's
# deployment package is read directly from S3 and the CodeUri source
# directory is never checked out).
data "archive_file" "lambda_code" {
  # Filtered for expression: gates on the code source being local AND avoids the
  # object/map type-unification error that a ternary (functions_with_defaults : {})
  # produces in Terraform ≥ 1.0 when functions_with_defaults is an object type
  # rather than map(any). Iterating local._function_names (a set(string)) yields a
  # consistent map(any) in both the populated and empty cases.
  for_each = {
    for func_name in local._function_names :
    func_name => local.functions_with_defaults[func_name]
    if var.lambda_code_source.type == "local"
  }

  type = "zip"
  # SAM per-function CodeUri: each function gets its own archive from its subdirectory.
  # node_modules are included because each CodeUri directory has its own dependencies.
  # Without CodeUri (standard SLS): all functions share one archive from lambda_code_path,
  # with dev dependencies excluded.
  source_dir  = try(each.value.code_uri, null) != null ? "${var.lambda_code_path}/${trimprefix(each.value.code_uri, "./")}" : var.lambda_code_path
  output_path = "${path.module}/.terraform/lambda-${each.key}.zip"

  excludes = try(each.value.code_uri, null) != null ? [] : [
    # Version control
    ".git",
    ".git/**",
    "**/.git/**",

    # Terraform files and state
    ".terraform",
    ".terraform/**",
    "**/.terraform/**",
    "*.terraform.lock.hcl",
    "**/.terraform.lock.hcl",
    ".terraform.tfstate.lock.info",
    "**/.terraform.tfstate.lock.info",
    "**/*.tf",
    "**/*.tftest.hcl",
    "**/*.tfstate",
    "**/*.tfstate.backup",
    "**/*.tfvars",

    # IDE and editor directories
    ".idea",
    ".idea/**",
    "**/.idea/**",
    ".vscode",
    ".vscode/**",
    "**/.vscode/**",
    ".claude",
    ".claude/**",
    "**/.claude/**",

    # Dependencies
    "node_modules",
    "node_modules/**",
    "**/node_modules/**",

    # OS files
    "**/.DS_Store",
    "**/Thumbs.db",

    # Project-specific directories (tests, docs, etc.)
    "tests",
    "tests/**",
    "examples",
    "examples/**",
    "agent-os",
    "agent-os/**",
    "docs",
    "docs/**",
    "**/*.md",
    "*.md",
  ]
}

# Lambda package size validation (local mode only — S3-sourced packages
# are AWS's responsibility to validate at upload time, and there is no local
# archive to measure).
resource "null_resource" "lambda_size_validation" {
  for_each = {
    for func_name in local._function_names :
    func_name => local.functions_with_defaults[func_name]
    if var.lambda_code_source.type == "local"
  }

  lifecycle {
    # Validate compressed package size (50 MB limit for direct upload)
    precondition {
      condition     = data.archive_file.lambda_code[each.key].output_size <= 52428800 # 50 MB in bytes
      error_message = "Lambda function '${each.key}' deployment package is ${floor(data.archive_file.lambda_code[each.key].output_size / 1048576)} MB (compressed), which exceeds AWS Lambda's 50 MB direct upload limit. Consider: 1) Using S3 for packages >50MB, 2) Reducing dependencies, 3) Using Lambda layers, or 4) Switching to container images for packages >250MB uncompressed."
    }

  }
}

# IAM execution role for each Lambda function (skipped for functions that
# declare an explicit Role — those are honored as-is).
resource "aws_iam_role" "lambda_execution" {
  for_each = {
    for fn, cfg in local.functions_with_defaults :
    fn => cfg if !try(local._function_has_explicit_role[fn], false)
  }

  name = "${try(local.parsed_config_resolved.service, "unknown")}-${local.provider_with_defaults.stage}-${each.key}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = contains(local.functions_with_cloudfront_events, each.key) ? [
          "lambda.amazonaws.com",
          "edgelambda.amazonaws.com"
        ] : ["lambda.amazonaws.com"]
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Service  = try(local.parsed_config_resolved.service, "unknown")
    Stage    = local.provider_with_defaults.stage
    Function = each.key
  }

  depends_on = [null_resource.config_validation]
}

# Attach basic execution policy for CloudWatch Logs
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  for_each = {
    for fn, cfg in local.functions_with_defaults :
    fn => cfg if !try(local._function_has_explicit_role[fn], false)
  }

  role       = aws_iam_role.lambda_execution[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach VPC access policy for functions with vpc_config
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  for_each = toset([
    for func_name in local._function_names : func_name
    if try(local._function_has_vpc[func_name], false) && !try(local._function_has_explicit_role[func_name], false)
  ])

  role       = aws_iam_role.lambda_execution[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Custom IAM policies from iamRoleStatements (Roadmap #3)
resource "aws_iam_role_policy" "lambda_custom_policy" {
  for_each = local.functions_with_policies

  name = "${try(local.parsed_config_resolved.service, "unknown")}-${local.provider_with_defaults.stage}-${each.key}-policy"
  role = aws_iam_role.lambda_execution[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for stmt in each.value : merge(
        {
          Effect   = stmt.Effect
          Action   = stmt.Action
          Resource = stmt.Resource
        },
        try(stmt.Condition, null) != null ? { Condition = stmt.Condition } : {}
      )
    ]
  })
}

# Lambda function resources
resource "aws_lambda_function" "functions" {
  for_each = local.functions_with_defaults

  # Explicit FunctionName from SAM template overrides the auto-generated name.
  function_name = try(each.value.name, null) != null ? each.value.name : "${try(local.parsed_config_resolved.service, "unknown")}-${local.provider_with_defaults.stage}-${each.key}"
  # Honor an explicit Role; otherwise use the per-function role created above.
  role = try(local._function_has_explicit_role[each.key], false) ? local._function_role_arn[each.key] : aws_iam_role.lambda_execution[each.key].arn

  # Code source: either local zip (data.archive_file) or S3 (artefact built
  # in CI and promoted via the SHA pin in var.lambda_code_source).
  filename         = var.lambda_code_source.type == "local" ? data.archive_file.lambda_code[each.key].output_path : null
  source_code_hash = var.lambda_code_source.type == "local" ? data.archive_file.lambda_code[each.key].output_base64sha256 : null
  s3_bucket        = var.lambda_code_source.type == "s3" ? var.lambda_code_source.bucket : null
  s3_key           = var.lambda_code_source.type == "s3" ? "${var.lambda_code_source.key_prefix}/${local.s3_artefact_names[each.key]}/${var.lambda_code_source.sha}.zip" : null

  # handler/runtime come from the structural template locals for SAM (always known at
  # plan); other config formats keep the resolved-config values.
  runtime     = var.config_format == "sam" ? try(local._function_runtime[each.key], each.value.runtime) : each.value.runtime
  handler     = var.config_format == "sam" ? try(local._function_handler[each.key], each.value.handler) : each.value.handler
  memory_size = each.value.memorySize
  timeout     = each.value.timeout
  # Lambda@Edge requires published versions for qualified_arn references
  publish = contains(local.functions_with_cloudfront_events, each.key)

  description   = try(each.value.description, null)
  architectures = try(each.value.architectures, null)

  dynamic "environment" {
    for_each = try(each.value.environment, null) != null ? [1] : []
    content {
      variables = each.value.environment
    }
  }

  dynamic "vpc_config" {
    for_each = try(length(each.value.vpc_config.subnet_ids), 0) > 0 ? [each.value.vpc_config] : []
    content {
      subnet_ids         = vpc_config.value.subnet_ids
      security_group_ids = vpc_config.value.security_group_ids
    }
  }

  dynamic "file_system_config" {
    for_each = try(each.value.file_system_configs, null) != null ? each.value.file_system_configs : []
    content {
      arn              = file_system_config.value.arn
      local_mount_path = file_system_config.value.local_mount_path
    }
  }

  tags = {
    Service  = try(local.parsed_config_resolved.service, "unknown")
    Stage    = local.provider_with_defaults.stage
    Function = each.key
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_iam_role_policy_attachment.lambda_vpc,
  ]
}

# Main validation resource
# This null_resource enforces parsing and schema validation before proceeding

resource "null_resource" "config_validation" {
  lifecycle {
    # Ensure file was read successfully. Skipped for the typescript format, whose
    # parser reads the file itself and reports read/parse failures through
    # local.typescript_all_errors (surfaced by the validation_errors check below).
    precondition {
      condition     = local.file_content != null || var.config_format == "typescript"
      error_message = "Failed to read configuration file at '${var.config_path}'. Please verify the file exists and is readable."
    }

    # Ensure parsing succeeded. Skipped for typescript for the same reason: a TS
    # parse failure is reported with a precise message via validation_errors.
    precondition {
      condition     = local.parsed_config != null || var.config_format == "typescript"
      error_message = "Failed to parse YAML configuration from '${var.config_path}'. Please verify the YAML syntax is valid."
    }

    # Ensure all schema validations passed
    precondition {
      condition     = length(local.validation_errors) == 0
      error_message = "Configuration validation failed with the following errors:\n- ${join("\n- ", local.validation_errors)}"
    }

    # Region override warning (non-blocking)
    precondition {
      condition     = length(local.region_warnings) == 0 || length(local.region_warnings) > 0
      error_message = join("\n", local.region_warnings)
    }
  }

  # Force display of warnings without blocking
  triggers = {
    warnings = length(local.region_warnings) > 0 ? join("\n", local.region_warnings) : ""
  }
}

# ============================================================================
# API Gateway Resources (Roadmap #4)
# ============================================================================

# REST API - Created only when HTTP events exist
resource "aws_api_gateway_rest_api" "this" {
  count = length(local.http_v1_events) > 0 ? 1 : 0

  name        = "${local.parsed_config_resolved.service}-${local.provider_with_defaults.stage}"
  description = "API Gateway for ${local.parsed_config_resolved.service}"

  endpoint_configuration {
    types = ["EDGE"]
  }

  depends_on = [null_resource.config_validation]
}

# API Gateway Resources - Depth 1 (root level paths like /users)
resource "aws_api_gateway_resource" "depth_1" {
  for_each = length(local.http_v1_events) > 0 ? local.resources_by_depth[1] : {}

  rest_api_id = aws_api_gateway_rest_api.this[0].id
  parent_id   = aws_api_gateway_rest_api.this[0].root_resource_id
  path_part   = each.value.path_part
}

# API Gateway Resources - Depth 2 (paths like /users/{id})
resource "aws_api_gateway_resource" "depth_2" {
  for_each = length(local.http_v1_events) > 0 && local.max_depth >= 2 ? local.resources_by_depth[2] : {}

  rest_api_id = aws_api_gateway_rest_api.this[0].id
  parent_id   = aws_api_gateway_resource.depth_1[each.value.parent_path].id
  path_part   = each.value.path_part
}

# API Gateway Resources - Depth 3 (paths like /users/{id}/posts)
resource "aws_api_gateway_resource" "depth_3" {
  for_each = length(local.http_v1_events) > 0 && local.max_depth >= 3 ? local.resources_by_depth[3] : {}

  rest_api_id = aws_api_gateway_rest_api.this[0].id
  parent_id   = aws_api_gateway_resource.depth_2[each.value.parent_path].id
  path_part   = each.value.path_part
}

# API Gateway Resources - Depth 4 (paths like /users/{id}/posts/{postId})
resource "aws_api_gateway_resource" "depth_4" {
  for_each = length(local.http_v1_events) > 0 && local.max_depth >= 4 ? local.resources_by_depth[4] : {}

  rest_api_id = aws_api_gateway_rest_api.this[0].id
  parent_id   = aws_api_gateway_resource.depth_3[each.value.parent_path].id
  path_part   = each.value.path_part
}

# Local to unify all depth resources for easy reference
locals {
  all_api_resources = merge(
    length(local.http_v1_events) > 0 ? aws_api_gateway_resource.depth_1 : {},
    length(local.http_v1_events) > 0 && local.max_depth >= 2 ? aws_api_gateway_resource.depth_2 : {},
    length(local.http_v1_events) > 0 && local.max_depth >= 3 ? aws_api_gateway_resource.depth_3 : {},
    length(local.http_v1_events) > 0 && local.max_depth >= 4 ? aws_api_gateway_resource.depth_4 : {}
  )
}

# API Gateway Methods - One per HTTP event
resource "aws_api_gateway_method" "endpoints" {
  # Key includes the path: one function can serve several paths with the same
  # method (e.g. GET /a and GET /b on a single handler), so function+method
  # alone is not unique and would collide into a duplicate for_each key.
  for_each = length(local.http_v1_events) > 0 ? {
    for event in local.http_v1_events :
    "${event.function_name}_${lower(event.http_method)}_${event.http_path}" => {
      function_name = event.function_name
      http_method   = event.http_method
      http_path     = event.http_path
    }
  } : {}

  rest_api_id   = aws_api_gateway_rest_api.this[0].id
  resource_id   = local.all_api_resources[each.value.http_path].id
  http_method   = each.value.http_method
  authorization = "NONE"
}

# API Gateway Lambda Integrations - AWS_PROXY type
resource "aws_api_gateway_integration" "lambda" {
  for_each = length(local.http_v1_events) > 0 ? {
    for event in local.http_v1_events :
    "${event.function_name}_${lower(event.http_method)}_${event.http_path}" => {
      function_name = event.function_name
      http_method   = event.http_method
      http_path     = event.http_path
    }
  } : {}

  rest_api_id = aws_api_gateway_rest_api.this[0].id
  resource_id = local.all_api_resources[each.value.http_path].id
  http_method = aws_api_gateway_method.endpoints["${each.value.function_name}_${lower(each.value.http_method)}_${each.value.http_path}"].http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${local.provider_with_defaults.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.functions[each.value.function_name].arn}/invocations"
}

# CORS OPTIONS Methods
resource "aws_api_gateway_method" "cors_options" {
  for_each = length(local.http_v1_events) > 0 ? local.cors_headers : {}

  rest_api_id   = aws_api_gateway_rest_api.this[0].id
  resource_id   = local.all_api_resources[each.key].id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# CORS OPTIONS Integrations - MOCK type
resource "aws_api_gateway_integration" "cors_options" {
  for_each = length(local.http_v1_events) > 0 ? local.cors_headers : {}

  rest_api_id = aws_api_gateway_rest_api.this[0].id
  resource_id = local.all_api_resources[each.key].id
  http_method = aws_api_gateway_method.cors_options[each.key].http_method

  type = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# CORS OPTIONS Method Response
resource "aws_api_gateway_method_response" "cors_options_200" {
  for_each = length(local.http_v1_events) > 0 ? local.cors_headers : {}

  rest_api_id = aws_api_gateway_rest_api.this[0].id
  resource_id = local.all_api_resources[each.key].id
  http_method = aws_api_gateway_method.cors_options[each.key].http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

# CORS OPTIONS Integration Response
resource "aws_api_gateway_integration_response" "cors_options_200" {
  for_each = length(local.http_v1_events) > 0 ? local.cors_headers : {}

  rest_api_id = aws_api_gateway_rest_api.this[0].id
  resource_id = local.all_api_resources[each.key].id
  http_method = aws_api_gateway_method.cors_options[each.key].http_method
  status_code = aws_api_gateway_method_response.cors_options_200[each.key].status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = each.value["Access-Control-Allow-Headers"]
    "method.response.header.Access-Control-Allow-Methods" = each.value["Access-Control-Allow-Methods"]
    "method.response.header.Access-Control-Allow-Origin"  = each.value["Access-Control-Allow-Origin"]
  }

  depends_on = [aws_api_gateway_integration.cors_options]
}

# Lambda Permissions - Allow API Gateway to invoke Lambda functions
resource "aws_lambda_permission" "api_gateway" {
  for_each = length(local.http_v1_events) > 0 ? local.functions_with_http_events : toset([])

  statement_id  = "AllowAPIGatewayInvoke-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.functions[each.key].function_name
  principal     = "apigateway.amazonaws.com"

  # Allow invocation from any stage/method on this API
  source_arn = "${aws_api_gateway_rest_api.this[0].execution_arn}/*/*"
}

# API Gateway Deployment - Triggered on configuration changes
resource "aws_api_gateway_deployment" "this" {
  count = length(local.http_v1_events) > 0 ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.this[0].id

  # Trigger redeployment when methods or integrations change
  triggers = {
    redeployment = sha1(jsonencode({
      methods           = keys(aws_api_gateway_method.endpoints)
      integrations      = keys(aws_api_gateway_integration.lambda)
      cors_methods      = keys(aws_api_gateway_method.cors_options)
      cors_integrations = keys(aws_api_gateway_integration.cors_options)
    }))
  }

  lifecycle {
    create_before_destroy = true
  }

  # Ensure all methods and integrations are created before deployment
  depends_on = [
    aws_api_gateway_method.endpoints,
    aws_api_gateway_integration.lambda,
    aws_api_gateway_method.cors_options,
    aws_api_gateway_integration.cors_options,
    aws_api_gateway_integration_response.cors_options_200
  ]
}

# API Gateway Stage
resource "aws_api_gateway_stage" "this" {
  count = length(local.http_v1_events) > 0 ? 1 : 0

  deployment_id = aws_api_gateway_deployment.this[0].id
  rest_api_id   = aws_api_gateway_rest_api.this[0].id
  stage_name    = local.provider_with_defaults.stage
}

# ============================================================================
# Custom Domain Module (Roadmap #12)
# ============================================================================

module "custom_domain" {
  source = "./modules/custom-domain"

  count = var.enable_custom_domain && try(local.provider_with_defaults.customDomain, null) != null && length(local.http_v1_events) > 0 ? 1 : 0

  domain_config        = local.provider_with_defaults.customDomain
  api_gateway_rest_api = aws_api_gateway_rest_api.this[0].id
  api_gateway_stage    = aws_api_gateway_stage.this[0].stage_name
  create_hosted_zone   = var.create_hosted_zone
  acm_certificate_arn  = var.acm_certificate_arn
  aws_region           = local.provider_with_defaults.region
}
