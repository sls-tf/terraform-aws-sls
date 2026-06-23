# ============================================================================
# Step Functions — AWS::Serverless::StateMachine / AWS::StepFunctions::StateMachine
# ============================================================================
# Creates an aws_sfn_state_machine from a SAM/CloudFormation state machine
# resource, plus an execution role derived from its Policies.
#
# Supported Properties:
#   Name                    -> state machine name
#   Type                    -> STANDARD (default) | EXPRESS
#   DefinitionUri           -> path to an Amazon States Language JSON file,
#                              relative to var.lambda_code_path
#   DefinitionSubstitutions -> ${Key} placeholders substituted into the
#                              definition (templatefile semantics). !GetAtt .Arn
#                              values resolve to the (deterministic) function ARNs.
#   Policies                -> LambdaInvokePolicy templates and/or inline
#                              Statement documents -> execution role policy.
#
# Definition/role values are read from the resolved parse; for_each keys come
# from the plan-time-known structural parse.

locals {
  # State machine resources, gated by resource_types.
  sam_state_machines = {
    for logical_id, resource in local._custom_resources_structure :
    logical_id => resource
    if contains(["AWS::Serverless::StateMachine", "AWS::StepFunctions::StateMachine"], try(resource.Type, ""))
    && (var.resource_types == null || contains(var.resource_types, try(resource.Type, "")))
  }

  # Per-state-machine derived config.
  sfn_config = {
    for logical_id, resource in local.sam_state_machines :
    logical_id => {
      name           = tostring(try(local.custom_resources_raw[logical_id].Properties.Name, "${try(local.parsed_config_resolved.service, "sam-service")}-${local.provider_with_defaults.stage}-${logical_id}"))
      type           = upper(tostring(try(local.custom_resources_raw[logical_id].Properties.Type, "STANDARD")))
      definition_uri = tostring(try(local._custom_resources_structure[logical_id].Properties.DefinitionUri, ""))
      substitutions = {
        for k, v in try(local.custom_resources_raw[logical_id].Properties.DefinitionSubstitutions, {}) :
        k => tostring(v)
      }

      # Lambda functions this state machine may invoke, from LambdaInvokePolicy
      # templates. FunctionName is a !Ref (marker) or a resolved name; map either
      # back to a function logical ID so aws_lambda_function.functions resolves.
      invoke_function_ids = [
        for policy in try(local.custom_resources_raw[logical_id].Properties.Policies, []) :
        try(
          local._function_name_to_logical[replace(tostring(policy.LambdaInvokePolicy.FunctionName), local._unresolved_ref_prefix, "")],
          replace(tostring(policy.LambdaInvokePolicy.FunctionName), local._unresolved_ref_prefix, "")
        )
        if try(policy.LambdaInvokePolicy, null) != null
      ]

      # Inline IAM statements from Policies entries that carry a Statement doc.
      inline_statements = flatten([
        for policy in try(local.custom_resources_raw[logical_id].Properties.Policies, []) : [
          for stmt in try(policy.Statement, []) : {
            Effect   = try(stmt.Effect, "Allow")
            Action   = try(tolist(stmt.Action), [tostring(try(stmt.Action, "*"))])
            Resource = try(tolist(stmt.Resource), [tostring(try(stmt.Resource, "*"))])
          }
        ]
      ])
    }
  }
}

# Execution role per state machine.
resource "aws_iam_role" "sfn" {
  for_each = local.sam_state_machines

  name = "${try(local.parsed_config_resolved.service, "sam-service")}-${local.provider_with_defaults.stage}-${each.key}-sfn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Service   = try(local.parsed_config_resolved.service, "sam-service")
    Stage     = local.provider_with_defaults.stage
    LogicalId = each.key
  }

  depends_on = [null_resource.config_validation]
}

# Inline policy: LambdaInvokePolicy targets + any inline statements.
resource "aws_iam_role_policy" "sfn" {
  for_each = {
    for logical_id, cfg in local.sfn_config :
    logical_id => cfg
    if length(cfg.invoke_function_ids) > 0 || length(cfg.inline_statements) > 0
  }

  name = "${try(local.parsed_config_resolved.service, "sam-service")}-${local.provider_with_defaults.stage}-${each.key}-sfn-policy"
  role = aws_iam_role.sfn[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      length(each.value.invoke_function_ids) > 0 ? [{
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
        Resource = flatten([
          for fid in each.value.invoke_function_ids : [
            aws_lambda_function.functions[fid].arn,
            "${aws_lambda_function.functions[fid].arn}:*"
          ]
        ])
      }] : [],
      [
        for stmt in each.value.inline_statements : {
          Effect   = stmt.Effect
          Action   = stmt.Action
          Resource = stmt.Resource
        }
      ]
    )
  })
}

resource "aws_sfn_state_machine" "this" {
  for_each = local.sam_state_machines

  name     = local.sfn_config[each.key].name
  role_arn = aws_iam_role.sfn[each.key].arn
  type     = local.sfn_config[each.key].type

  # DefinitionSubstitutions use ${Key} placeholders — exactly templatefile's
  # interpolation syntax. The substitutions map must cover every ${...} in the
  # definition (the CloudFormation contract).
  definition = templatefile(
    "${var.lambda_code_path}/${local.sfn_config[each.key].definition_uri}",
    local.sfn_config[each.key].substitutions
  )

  depends_on = [null_resource.config_validation]
}
