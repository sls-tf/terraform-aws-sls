# ============================================================================
# AWS SAM Template Parser
# ============================================================================
# Parses AWS SAM template.yaml files and translates them to the SLS-compatible
# config structure used throughout the rest of the module. All existing resource
# blocks (Lambda, API Gateway, S3, DynamoDB, SQS, etc.) consume this translated
# config without modification.

# Terraform's yamldecode() rejects CloudFormation intrinsic function tags
# (!Ref, !Sub, !If, etc.) with "unsupported tag" errors.  Use js-yaml via an
# external data source that fully evaluates all CFN intrinsics against the
# supplied parameter values before returning a plain JSON-serialisable object.
data "external" "sam_yaml" {
  count = var.config_format == "sam" ? 1 : 0

  # sam-preprocessor.js depends only on a vendored, tree-shaken js-yaml committed
  # under scripts/vendor/ (plus Node built-ins), so the SAM path needs no
  # node_modules and no npm install — `terraform plan` stays self-contained and
  # works in Node-only, offline, and read-only environments. Requires `node` on PATH.
  program = [
    "node", "${path.module}/scripts/sam-preprocessor.js"
  ]

  query = {
    config_path = var.config_path
    parameters  = jsonencode(var.sam_template_parameters)
    region      = data.aws_region.current.region
    account_id  = data.aws_caller_identity.current.account_id
    strict      = tostring(var.strict_sam_intrinsics)
  }
}

# Discover which template Parameters the Conditions section references. Static
# query (no parameter values) → always plan-known. These are the parameters that
# decide resource EXISTENCE (a resource's `Condition`), so the structure parse
# below must see their real values; every OTHER parameter stays empty so an
# unknown-at-plan value can't make the structure read unknown.
data "external" "sam_condition_params" {
  count = var.config_format == "sam" ? 1 : 0

  program = [
    "node", "${path.module}/scripts/sam-preprocessor.js"
  ]

  query = {
    config_path = var.config_path
    mode        = "condition-params"
  }
}

# Structural (plan-time-known) parse of the SAM template.
#
# The resolved parse above embeds var.sam_template_parameters in its query. When a
# consumer passes parameter values computed in the SAME plan (e.g.
# aws_secretsmanager_secret.x.arn on a greenfield/ephemeral account), the query is
# unknown at plan, Terraform DEFERS the data source read to apply, and sam_raw —
# and every local derived from it — becomes wholly unknown. That collapses every
# for_each/count key in the module ("Invalid for_each argument"). On already-applied
# environments the same parameters are known from state, the read happens at plan,
# and everything works — which is why the failure is greenfield-only.
#
# This second read resolves intrinsics against template Defaults plus ONLY the
# condition-relevant parameters (local.sam_structure_params) — so a resource's
# `Condition` evaluates against its real per-env value and resources are kept/
# dropped from the for_each KEYS correctly, while every other (possibly
# unknown-at-plan) parameter stays empty so the read remains plan-known. It still
# drives STRUCTURE only — logical IDs, Types, event shapes, handler/runtime/
# CodeUri, property PRESENCE, and condition-gated existence — never non-condition
# parameter VALUES. Those keep coming from local.sam_raw so applied environments
# see exactly the same rendered configuration as before.
#
# Constraint: any parameter a `Condition` references must be plan-known (e.g. an
# SSM/remote-state read, not an in-plan resource attribute) — otherwise this read
# defers and for_each keys go unknown, exactly as the resolved parse does.
data "external" "sam_yaml_structure" {
  count = var.config_format == "sam" ? 1 : 0

  program = [
    "node", "${path.module}/scripts/sam-preprocessor.js"
  ]

  query = {
    config_path = var.config_path
    parameters  = jsonencode(local.sam_structure_params)
    region      = data.aws_region.current.region
    account_id  = data.aws_caller_identity.current.account_id
    strict      = "false"
  }
}

locals {
  # Parameter names referenced by the template's Conditions (from the static
  # discovery read). Empty for templates with no parameter-driven conditions —
  # in which case the structure parse runs with an empty parameter set exactly
  # as before.
  sam_condition_param_names = var.config_format == "sam" ? try(
    jsondecode(data.external.sam_condition_params[0].result.content).condition_params,
    []
  ) : []

  # The condition-relevant subset of the caller's parameters, fed to the
  # structure parse so resource `Condition`s resolve against real per-env values
  # while non-condition parameters stay empty (and thus can't make the read
  # unknown at plan).
  sam_structure_params = {
    for k in local.sam_condition_param_names :
    k => tostring(try(var.sam_template_parameters[k], ""))
  }

  # Raw SAM parse — only active when config_format is "sam".
  # Decoded from the external preprocessor result (handles !Ref/!Sub/!If etc.).
  sam_raw = var.config_format == "sam" ? (
    try(data.external.sam_yaml[0].result.content, "") != "" ?
    try(jsondecode(data.external.sam_yaml[0].result.content), null) :
    null
  ) : null

  # Structural twin of sam_raw — identical document shape, parameter references
  # resolved against Defaults/markers only. Always known at plan. Use this (and
  # only this) for anything that feeds for_each/count keys, `if` filters, or
  # dynamic-block conditions. Constraint this implies for templates: Parameters
  # must not change template STRUCTURE (e.g. an !If on a parameter that adds or
  # removes resources/events) — the standard Terraform for_each constraint.
  sam_structure = var.config_format == "sam" ? (
    try(data.external.sam_yaml_structure[0].result.content, "") != "" ?
    try(jsondecode(data.external.sam_yaml_structure[0].result.content), null) :
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
  # Structural source: bucket keys feed event/bucket for_each keys downstream.
  sam_s3_bucket_names = var.config_format == "sam" && local.sam_structure != null ? {
    for logical_id, resource in try(local.sam_structure.Resources, {}) :
    logical_id => try(
      resource.Properties.BucketName,
      lower(logical_id)
    )
    if try(resource.Type, "") == "AWS::S3::Bucket"
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

  # Structural source: event maps (schedule_event_map, eventbridge_event_map,
  # s3/sqs/stream wiring, http_events → API Gateway resources) all derive their
  # for_each KEYS from these lists, so the lists must be known at plan. This means
  # event Properties (Schedule rate, Queue/Stream ARN, paths) are resolved against
  # template Defaults / pseudo-params (region, account id) — NOT against
  # var.sam_template_parameters. Constraint: do not feed event Properties from
  # template Parameters; use literals, !Sub with pseudo-params, or !Ref/!GetAtt to
  # co-defined template resources (all identical in both parses).
  sam_function_event_json_strings = var.config_format == "sam" && local.sam_structure != null ? {
    for logical_id, resource in try(local.sam_structure.Resources, {}) :
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
    # JSON-laundered to the dynamic `any` type: the SimpleTable-translation branch
    # and the pass-through `resource` branch are differently-shaped objects, which
    # a bare ternary cannot unify ("Inconsistent conditional result types"). Both
    # branches are encoded to a string and decoded once — the same idiom used for
    # sam_function_events above.
    logical_id => jsondecode(
      # AWS::Serverless::SimpleTable → AWS::DynamoDB::Table (PAY_PER_REQUEST)
      try(resource.Type, "") == "AWS::Serverless::SimpleTable" ? jsonencode({
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
      }) :

      # All other resource types (AWS::S3::Bucket, AWS::DynamoDB::Table, etc.)
      # pass through unchanged for custom_resources.tf to handle.
      jsonencode(resource)
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

  # Structural twin of sam_resources_translated: logical ID → translated
  # CloudFormation resource, from the plan-time-known parse. Drives custom-resource
  # categorization (Type) and property-PRESENCE checks (VersioningConfiguration,
  # AccessControl) so the custom_resources.tf for_each keys stay known at plan even
  # when sam_template_parameters carry co-planned (unknown) values. Resource VALUES
  # continue to come from the resolved document.
  # JSON-laundered to the dynamic `any` type (same idiom as sam_resources_translated):
  # the per-resource objects are differently shaped, which a bare map/ternary cannot
  # unify ("Inconsistent conditional result types").
  sam_custom_resources_structure = jsondecode(
    var.config_format == "sam" && local.sam_structure != null ? jsonencode({
      for logical_id, resource in try(local.sam_structure.Resources, {}) :
      logical_id => jsondecode(
        # AWS::Serverless::SimpleTable → AWS::DynamoDB::Table (same translation as above)
        try(resource.Type, "") == "AWS::Serverless::SimpleTable" ? jsonencode({
          Type       = "AWS::DynamoDB::Table"
          Properties = try(resource.Properties, {})
        }) :
        jsonencode(resource)
      )
      if !contains(
        ["AWS::Serverless::Function", "AWS::Serverless::Api", "AWS::Serverless::LayerVersion", "AWS::Serverless::Application"],
        try(resource.Type, "")
      )
    }) : jsonencode({})
  )

  # ============================================================================
  # SAM → SLS Config Translation
  # ============================================================================
  # Produces an SLS-compatible config object consumed by the rest of the module.
  # This single translation point lets all existing resource blocks work with
  # SAM templates without any changes to downstream code.

  sam_as_sls_config = var.config_format == "sam" && local.sam_raw != null ? {
    # SAM has no "service" field; prefer Metadata.ServiceName (short, stable),
    # then fall back to "sam-service". Description is intentionally NOT used here
    # because it is often too long for IAM role names (64-char limit).
    service = try(
      length(try(local.sam_raw.Metadata.ServiceName, "")) > 0 ? local.sam_raw.Metadata.ServiceName : "sam-service",
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
        # Explicit FunctionName (already resolved by the preprocessor).
        name = try(tostring(resource.Properties.FunctionName), null)

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
        # SubnetIds may be a list (already resolved by the preprocessor) or a
        # comma-delimited string (CommaDelimitedList param already resolved).
        vpc_config = try(resource.Properties.VpcConfig, null) != null ? {
          subnet_ids = try(
            tolist(resource.Properties.VpcConfig.SubnetIds),
            compact(split(",", tostring(try(resource.Properties.VpcConfig.SubnetIds, ""))))
          )
          security_group_ids = [
            for sg in try(tolist(resource.Properties.VpcConfig.SecurityGroupIds), []) :
            tostring(sg)
          ]
        } : null

        # EFS file system configs (ARN already resolved by the preprocessor).
        file_system_configs = length(try(tolist(resource.Properties.FileSystemConfigs), [])) > 0 ? [
          for fsc in tolist(resource.Properties.FileSystemConfigs) : {
            arn              = tostring(fsc.Arn)
            local_mount_path = try(tostring(fsc.LocalMountPath), "/mnt/efs")
          }
        ] : null

        # Global env vars merged with function-level; function wins on conflict.
        # All values are already resolved by the preprocessor. A value that is
        # NOT scalar at this point means an unsupported/unresolved intrinsic (or a
        # literal list/map) leaked through — always a bug. Rather than let
        # tostring() raise an opaque type error here, keep a sentinel string so
        # the build stays evaluable and surface a clear, named error via
        # local.sam_env_nonscalar_errors (checked by null_resource.config_validation).
        environment = {
          for k, v in merge(
            try(local.sam_function_globals.Environment.Variables, {}),
            try(resource.Properties.Environment.Variables, {})
          ) :
          k => can(tostring(v)) ? tostring(try(v, "")) : "<<unresolved-intrinsic>>"
        }

        # Translate inline SAM policy documents to iamRoleStatements.
        # All intrinsic functions are already resolved by the preprocessor, so
        # values here are plain strings/lists with no CFN constructs remaining.
        # !If-gated policies resolve to their correct branch (or are absent when
        # the false branch was AWS::NoValue, which the preprocessor filters out).
        # Iterate the Policies list directly (no tolist): a SAM Policies list is
        # heterogeneous when it mixes policy templates (e.g. `VPCAccessPolicy: {}`)
        # with inline `Statement` documents — tolist() can't unify those object
        # types and throws, which `try` swallows to `[]`, silently dropping the
        # function's entire policy. Likewise iterate Statement directly rather than
        # via a `? [...] : []` ternary: the ternary's two branches are length-typed
        # tuples (`tuple([obj,obj])` vs `tuple([])`) that Terraform cannot unify for
        # complex object elements, raising "Inconsistent conditional result types".
        # A policy-template entry has no `.Statement`, so it simply yields nothing.
        iamRoleStatements = flatten([
          for policy in try(resource.Properties.Policies, []) : [
            for stmt in try(policy.Statement, []) : {
              Effect = try(stmt.Effect, "Allow")
              Action = try(tolist(stmt.Action), [tostring(try(stmt.Action, "*"))])
              Resource = try(
                compact([for r in tolist(stmt.Resource) : can(tostring(r)) ? tostring(r) : null]),
                can(tostring(stmt.Resource)) ? [tostring(stmt.Resource)] : ["*"]
              )
              # Preserve IAM Condition block (e.g. StringEquals, ArnLike) if present
              Condition = try(stmt.Condition, null)
            }
            # Skip statements whose Resource list is empty (all-NoValue !If branches)
            if length(try(
              compact([for r in tolist(stmt.Resource) : can(tostring(r)) ? tostring(r) : null]),
              can(tostring(stmt.Resource)) ? [tostring(stmt.Resource)] : ["*"]
            )) > 0
          ]
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
