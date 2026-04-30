# ============================================================================
# AWS SAM Template Parser
# ============================================================================
# Parses AWS SAM template.yaml files and translates them to the SLS-compatible
# config structure used throughout the rest of the module. All existing resource
# blocks (Lambda, API Gateway, S3, DynamoDB, SQS, etc.) consume this translated
# config without modification.

# Terraform's yamldecode() rejects CloudFormation intrinsic function tags
# (!Ref, !Sub, !If, etc.) with "unsupported tag" errors rather than stripping
# them silently.  Use js-yaml via an external data source, which treats those
# tags as transparent wrappers returning their underlying value unchanged.
data "external" "sam_yaml" {
  count = var.config_format == "sam" ? 1 : 0

  # Auto-install js-yaml if node_modules is absent (first run after module download).
  # Wraps sam-preprocessor.js which needs js-yaml from scripts/package.json.
  program = [
    "bash", "-c",
    "SCRIPTS=\"${path.module}/scripts\" && { [ -d \"$SCRIPTS/node_modules\" ] || npm install --silent --prefix \"$SCRIPTS\" >&2; } && node \"$SCRIPTS/sam-preprocessor.js\""
  ]

  query = {
    config_path = var.config_path
  }
}

locals {
  # Raw SAM parse — only active when config_format is "sam".
  # Decoded from the external preprocessor result (handles !Ref/!Sub/!If etc.).
  sam_raw = var.config_format == "sam" ? (
    try(data.external.sam_yaml[0].result.content, "") != "" ?
    try(jsondecode(data.external.sam_yaml[0].result.content), null) :
    null
  ) : null

  # Resolve template Parameters: prefer values from var.sam_template_parameters,
  # fall back to the Default defined in the template.
  sam_parameters = var.config_format == "sam" && local.sam_raw != null ? {
    for param_name, param_def in try(local.sam_raw.Parameters, {}) :
    param_name => try(
      var.sam_template_parameters[param_name],
      tostring(try(param_def.Default, ""))
    )
  } : {}

  # Globals.Function — applied to all functions unless overridden per-function.
  # null (not {}) so the conditional types are compatible; all callers use try().
  sam_function_globals = var.config_format == "sam" && local.sam_raw != null ? try(
    local.sam_raw.Globals.Function,
    null
  ) : null

  # Globals.Api — applied to all API resources
  sam_api_globals = var.config_format == "sam" && local.sam_raw != null ? try(
    local.sam_raw.Globals.Api,
    null
  ) : null

  # Helper: map S3 bucket logical IDs to their actual bucket names.
  # Used to resolve !Ref references in S3 event Properties.Bucket.
  sam_s3_bucket_names = var.config_format == "sam" && local.sam_raw != null ? {
    for logical_id, resource in try(local.sam_raw.Resources, {}) :
    logical_id => try(
      resource.Properties.BucketName,
      lower(logical_id)
    )
    if try(resource.Type, "") == "AWS::S3::Bucket"
  } : {}

  # ============================================================================
  # SAM !Ref / !Sub Resolution
  # ============================================================================
  # yamldecode strips CloudFormation intrinsic function tags silently:
  #   !Ref Foo        → "Foo"          (scalar string, tag discarded)
  #   !Sub "${A}-b"   → "${A}-b"       (string with literal ${...} sequences)
  #   !Select [0, !Ref X] → [0, "X"]  (list, handled separately in env vars)
  #
  # sam_resolved pre-computes every resolution so the sam_as_sls_config block
  # can do a simple lookup without repeating the split/join logic per property.

  # Merged parameter map: template Parameters + AWS CloudFormation pseudo-parameters.
  sam_all_params = var.config_format == "sam" && local.sam_raw != null ? merge(
    local.sam_parameters,
    {
      "AWS::Region"    = data.aws_region.current.name
      "AWS::AccountId" = data.aws_caller_identity.current.account_id
      "AWS::NoValue"   = ""
      "AWS::Partition" = "aws"
    }
  ) : {}

  # Collect every raw string that may require resolution.
  # Includes: FunctionName, env var values, VPC refs, EFS ARNs, IAM Resource values.
  sam_all_raw_strings = var.config_format == "sam" && local.sam_raw != null ? distinct(compact(flatten([
    for logical_id, resource in try(local.sam_raw.Resources, {}) : [
      # FunctionName (from !Sub "${NamePrefix}-create-schema" etc.)
      can(tostring(resource.Properties.FunctionName)) ? [tostring(resource.Properties.FunctionName)] : [],

      # Environment variable values — string-typed only; list values from !Select
      # are resolved inline in sam_as_sls_config
      [for v in values(try(resource.Properties.Environment.Variables, {})) :
        can(tostring(v)) ? tostring(v) : ""],
      [for v in values(try(local.sam_function_globals.Environment.Variables, {})) :
        can(tostring(v)) ? tostring(v) : ""],

      # VPC SubnetIds: !Ref to a CommaDelimitedList param → plain string after tag-strip
      can(tostring(resource.Properties.VpcConfig.SubnetIds)) ?
        [tostring(resource.Properties.VpcConfig.SubnetIds)] : [],

      # VPC SecurityGroupIds: list of !Ref strings
      [for sg in try(tolist(resource.Properties.VpcConfig.SecurityGroupIds), []) :
        can(tostring(sg)) ? tostring(sg) : ""],

      # EFS FileSystemConfig ARN references
      [for fsc in try(tolist(resource.Properties.FileSystemConfigs), []) :
        can(tostring(fsc.Arn)) ? tostring(fsc.Arn) : ""],

      # IAM policy Resource values (!Sub ARNs, !Ref param names, literal strings)
      flatten([for policy in try(tolist(resource.Properties.Policies), []) :
        can(policy.Statement) ? flatten([
          for stmt in try(tolist(policy.Statement), []) :
          try(
            [for r in tolist(stmt.Resource) :
              can(tostring(r)) ? tostring(r) : ""
              if can(tostring(r))
            ],
            can(tostring(stmt.Resource)) ? [tostring(stmt.Resource)] : []
          )
        ]) : []
      ])
    ]
    if try(resource.Type, "") == "AWS::Serverless::Function"
  ]))) : []

  # Resolution map: raw_string → resolved_string.
  #
  # Two strategies:
  #   !Ref Param:    entire string equals a parameter name → direct lookup
  #   !Sub "${A}-b": contains ${...} sequences → split on ${ and substitute each
  #
  # Unresolved placeholders (unknown params) are preserved as "${Name}" so that
  # downstream errors clearly identify the missing parameter.
  sam_resolved = var.config_format == "sam" && local.sam_raw != null ? {
    for raw_str in local.sam_all_raw_strings :
    raw_str => (
      # Pure !Ref: the whole string is a parameter / pseudo-parameter name
      can(local.sam_all_params[raw_str]) ?
        local.sam_all_params[raw_str] :
      # No ${...} patterns: return the literal as-is
      length(split("$${", raw_str)) == 1 ?
        raw_str :
      # !Sub: substitute each ${Param} placeholder using split/join
      join("", flatten([
        [split("$${", raw_str)[0]],
        [for piece in slice(split("$${", raw_str), 1, length(split("$${", raw_str))) : [
          lookup(local.sam_all_params, split("}", piece)[0], "$${${split("}", piece)[0]}}"),
          join("}", slice(split("}", piece), 1, length(split("}", piece))))
        ]]
      ]))
    )
  } : {}

  # ============================================================================
  # SAM Event Translation
  # ============================================================================
  # Translates SAM event types to SLS-compatible event objects.
  #
  # Each branch of the ternary chain returns jsonencode(...) — always a string —
  # so the overall expression is type-consistent. This list of JSON strings is
  # decoded back to list(any) in sam_function_events, matching what yamldecode
  # produces for native SLS event lists. The can(event.X) checks in the existing
  # event parsing code then work correctly against these decoded values.

  sam_function_event_json_strings = var.config_format == "sam" && local.sam_raw != null ? {
    for logical_id, resource in try(local.sam_raw.Resources, {}) :
    logical_id => [
      for event_name, event in try(resource.Properties.Events, {}) :
      (
        # Api / HttpApi → http
        contains(["Api", "HttpApi"], try(event.Type, "")) ? jsonencode({
          http = {
            path   = try(event.Properties.Path, "/")
            method = lower(try(event.Properties.Method, "any"))
          }
        }) :

        # S3 → s3 (always marked existing=true since SAM S3 events reference buckets
        # that are created either via the Resources section or pre-existing)
        try(event.Type, "") == "S3" ? jsonencode({
          s3 = {
            bucket = try(
              local.sam_s3_bucket_names[tostring(event.Properties.Bucket)],
              lower(tostring(try(event.Properties.Bucket, event_name)))
            )
            event    = try(event.Properties.Events, "s3:ObjectCreated:*")
            existing = true
            rules = [
              for rule in try(event.Properties.Filter.S3Key.Rules, []) : {
                prefix = try(rule.Name, "") == "prefix" ? tostring(try(rule.Value, null)) : null
                suffix = try(rule.Name, "") == "suffix" ? tostring(try(rule.Value, null)) : null
              }
              if contains(["prefix", "suffix"], try(rule.Name, ""))
            ]
          }
        }) :

        # DynamoDB → stream
        # !GetAtt references (e.g. "MyTable.StreamArn") are preserved as strings;
        # ARN format validation is skipped for SAM format in locals.tf.
        try(event.Type, "") == "DynamoDB" ? jsonencode({
          stream = {
            arn              = tostring(try(event.Properties.Stream, ""))
            startingPosition = try(event.Properties.StartingPosition, "LATEST")
            batchSize        = try(event.Properties.BatchSize, 100)
          }
        }) :

        # SQS → sqs
        # !Ref references (e.g. "MyQueue") are preserved as strings;
        # ARN format validation is skipped for SAM format in locals.tf.
        try(event.Type, "") == "SQS" ? jsonencode({
          sqs = {
            arn       = tostring(try(event.Properties.Queue, ""))
            batchSize = try(event.Properties.BatchSize, 10)
          }
        }) :

        # Schedule → schedule
        try(event.Type, "") == "Schedule" ? jsonencode({
          schedule = try(event.Properties.Schedule, "rate(5 minutes)")
        }) :

        # EventBridgeRule → eventBridge
        try(event.Type, "") == "EventBridgeRule" ? jsonencode({
          eventBridge = {
            pattern  = try(event.Properties.Pattern, {})
            eventBus = tostring(try(event.Properties.EventBusName, "default"))
            enabled  = try(event.Properties.State, "ENABLED") == "ENABLED"
          }
        }) :

        # Fallback — filtered out by the if clause below
        jsonencode(null)
      )
      if contains(["Api", "HttpApi", "S3", "DynamoDB", "SQS", "Schedule", "EventBridgeRule"], try(event.Type, ""))
    ]
    if try(resource.Type, "") == "AWS::Serverless::Function"
  } : {}

  # Decode JSON strings back to list(any) — the same dynamic structure that
  # yamldecode produces for native SLS event lists.
  sam_function_events = {
    for logical_id, json_strings in local.sam_function_event_json_strings :
    logical_id => length(json_strings) > 0 ? jsondecode("[${join(",", json_strings)}]") : []
  }

  # ============================================================================
  # Non-Function Resource Translation
  # ============================================================================
  # Translates SAM-specific resource types to CloudFormation-equivalent types
  # that custom_resources.tf already handles, then passes everything else through.

  sam_resources_translated = var.config_format == "sam" && local.sam_raw != null ? {
    for logical_id, resource in try(local.sam_raw.Resources, {}) :
    logical_id => (
      # AWS::Serverless::SimpleTable → AWS::DynamoDB::Table (PAY_PER_REQUEST)
      try(resource.Type, "") == "AWS::Serverless::SimpleTable" ? {
        Type = "AWS::DynamoDB::Table"
        Properties = {
          TableName   = try(resource.Properties.TableName, logical_id)
          BillingMode = "PAY_PER_REQUEST"
          AttributeDefinitions = [{
            AttributeName = try(resource.Properties.PrimaryKey.Name, "id")
            AttributeType = (
              try(resource.Properties.PrimaryKey.Type, "String") == "Number" ? "N" :
              try(resource.Properties.PrimaryKey.Type, "String") == "Binary" ? "B" : "S"
            )
          }]
          KeySchema = [{
            AttributeName = try(resource.Properties.PrimaryKey.Name, "id")
            KeyType       = "HASH"
          }]
          Tags = try(resource.Properties.Tags, null)
        }
      } :

      # All other resource types (AWS::S3::Bucket, AWS::DynamoDB::Table, etc.)
      # pass through unchanged for custom_resources.tf to handle.
      resource
    )
    # Exclude SAM-specific types that are handled elsewhere:
    # - Function → becomes a Lambda function via functions map
    # - Api → route table handled via http events on functions
    # - LayerVersion and Application → not yet supported, excluded silently
    if !contains(
      ["AWS::Serverless::Function", "AWS::Serverless::Api", "AWS::Serverless::LayerVersion", "AWS::Serverless::Application"],
      try(resource.Type, "")
    )
  } : {}

  # ============================================================================
  # SAM → SLS Config Translation
  # ============================================================================
  # Produces an SLS-compatible config object consumed by the rest of the module.
  # This single translation point lets all existing resource blocks work with
  # SAM templates without any changes to downstream code.

  sam_as_sls_config = var.config_format == "sam" && local.sam_raw != null ? {
    # SAM has no "service" field; use Description if provided, else a safe default.
    service = try(
      length(local.sam_raw.Description) > 0 ? local.sam_raw.Description : "sam-service",
      "sam-service"
    )

    provider = {
      name = "aws"

      # Runtime from Globals.Function; individual functions can override per-function.
      runtime = try(local.sam_function_globals.Runtime, null)

      region     = "us-east-1"
      stage      = "dev"
      memorySize = try(local.sam_function_globals.MemorySize, 1024)
      timeout    = try(local.sam_function_globals.Timeout, 6)
    }

    functions = {
      for logical_id, resource in try(local.sam_raw.Resources, {}) :
      logical_id => {
        # Explicit FunctionName (from !Sub or plain string) overrides the
        # auto-generated "{service}-{stage}-{logical_id}" name in main.tf.
        name = try(resource.Properties.FunctionName, null) != null ? lookup(
          local.sam_resolved,
          tostring(resource.Properties.FunctionName),
          tostring(resource.Properties.FunctionName)
        ) : null

        # CodeUri: per-function source directory (SAM-specific).
        # main.tf uses this as source_dir for the per-function archive.
        code_uri = try(tostring(resource.Properties.CodeUri), null)

        handler     = try(resource.Properties.Handler, "index.handler")
        runtime     = try(resource.Properties.Runtime, null)
        description = try(resource.Properties.Description, null)
        memorySize  = try(resource.Properties.MemorySize, null)
        timeout     = try(resource.Properties.Timeout, null)

        # Architectures: ["arm64"] or ["x86_64"]; null defers to Lambda default (x86_64)
        architectures = try(tolist(resource.Properties.Architectures), null)

        # VPC configuration.
        # SubnetIds is typically !Ref to a CommaDelimitedList param — yamldecode
        # strips the tag, leaving a plain string that we resolve then split on comma.
        vpc_config = try(resource.Properties.VpcConfig, null) != null ? {
          subnet_ids = try(
            tolist(resource.Properties.VpcConfig.SubnetIds),
            compact(split(",", lookup(local.sam_resolved,
              tostring(resource.Properties.VpcConfig.SubnetIds), "")))
          )
          security_group_ids = [
            for sg in try(tolist(resource.Properties.VpcConfig.SecurityGroupIds), []) :
            lookup(local.sam_resolved, tostring(sg), tostring(sg))
          ]
        } : null

        # EFS file system configs
        file_system_configs = length(try(tolist(resource.Properties.FileSystemConfigs), [])) > 0 ? [
          for fsc in tolist(resource.Properties.FileSystemConfigs) : {
            arn              = lookup(local.sam_resolved, tostring(fsc.Arn), tostring(fsc.Arn))
            local_mount_path = try(tostring(fsc.LocalMountPath), "/mnt/efs")
          }
        ] : null

        # Global env vars merged with function-level; function wins on conflict.
        # All values are resolved via sam_resolved (!Ref param → value, !Sub → substituted).
        # !Select [N, !Ref CommaDelimitedListParam] produces a list [index, "Param"] after
        # tag-stripping — detected by !can(tostring(v)) and resolved by splitting on comma.
        environment = {
          for k, v in merge(
            try(local.sam_function_globals.Environment.Variables, {}),
            try(resource.Properties.Environment.Variables, {})
          ) :
          k => (
            # !Select [N, !Ref ListParam]: yamldecode gives [index, "ParamName"]
            !can(tostring(v)) ? try(
              compact(split(",", lookup(local.sam_all_params, tostring(try(v[1], "")), "")))[tonumber(try(v[0], 0))],
              ""
            ) :
            # String value: look up resolved form, fall back to raw string
            lookup(local.sam_resolved, tostring(v), tostring(v))
          )
        }

        # Translate inline SAM policy documents to iamRoleStatements.
        # Resource values are resolved via sam_resolved so !Sub ARNs get correct
        # region/account substitution. !If constructs (mixed-type lists) fall back
        # to ["*"] since CloudFormation Conditions can't be evaluated at plan time.
        iamRoleStatements = flatten([
          for policy in try(tolist(resource.Properties.Policies), []) :
          can(policy.Statement) ? [
            for stmt in try(tolist(policy.Statement), []) : {
              Effect = try(stmt.Effect, "Allow")
              Action = try(tolist(stmt.Action), [tostring(try(stmt.Action, "*"))])
              Resource = try(
                [for r in tolist(stmt.Resource) :
                  lookup(local.sam_resolved, tostring(r), tostring(r))
                  if can(tostring(r))
                ],
                can(tostring(stmt.Resource)) ?
                  [lookup(local.sam_resolved, tostring(stmt.Resource), tostring(stmt.Resource))] :
                  ["*"]
              )
            }
          ] : []
        ])

        events = try(local.sam_function_events[logical_id], [])
      }
      if try(resource.Type, "") == "AWS::Serverless::Function"
    }

    # Non-function resources translated to CloudFormation-compatible types
    resources = length(local.sam_resources_translated) > 0 ? {
      Resources = local.sam_resources_translated
    } : null
  } : null
}
