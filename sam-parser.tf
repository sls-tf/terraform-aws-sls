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
  sam_structure_params = merge(
    {
      for k in local.sam_condition_param_names :
      k => tostring(try(var.sam_template_parameters[k], ""))
    },
    # Caller-declared structural parameters: known-at-plan params (e.g. an
    # environment suffix used in !Sub resource names/ARNs) that must resolve in
    # the structural parse so event/cross-resource names match the resolved
    # resources. Only safe for params whose values are always known at plan
    # (literals/SSM/remote-state) — never in-plan resource attributes, which
    # would defer the structural read and collapse for_each keys.
    {
      for k in var.structural_sam_parameters :
      k => tostring(try(var.sam_template_parameters[k], ""))
      if can(var.sam_template_parameters[k])
    }
  )

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

  # Errors from the PLAN-KNOWN preprocessor reads, surfaced for a LOUD precondition.
  #
  # scripts/sam-preprocessor.js emits {content, error}: on any failure (file not
  # found, malformed YAML, an unresolved intrinsic in strict mode, …) it returns
  # content="" plus a non-empty `error`. The parse locals above coalesce empty
  # content to null (sam_structure) and the condition-params read swallows its error
  # via try() — so a failure in EITHER of these reads silently produced a module with
  # ZERO resources (the structure read drives every for_each KEY), the failure only
  # surfacing far downstream (e.g. an aws_lambda_permission "Function not found" in a
  # consuming module, hours later).
  #
  # We deliberately check the STRUCTURE and CONDITION-PARAMS reads here, NOT the
  # resolved (sam_yaml) read: sam-validation.tf already reports sam_yaml's error, and
  # on a greenfield/ephemeral plan sam_yaml embeds in-plan parameter values, DEFERS to
  # apply, and its error is unknown — so checking it can't fail at plan. The structure
  # read (condition-relevant params only) and condition-params read (no params) stay
  # plan-known, so a failure in them is catchable at plan. compact() drops the empty
  # (success) strings.
  sam_preprocessor_errors = var.config_format == "sam" ? compact([
    try(data.external.sam_yaml_structure[0].result.error, ""),
    try(data.external.sam_condition_params[0].result.error, ""),
  ]) : []

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

  # ============================================================================
  # SAM HttpApi (apigatewayv2) Authorizer Parsing
  # ============================================================================
  # SAM declares HTTP API Lambda authorizers under an AWS::Serverless::HttpApi
  # resource's Properties.Auth.Authorizers and/or Globals.HttpApi.Auth.Authorizers,
  # keyed by authorizer name. An HttpApi function event then references one by name
  # via Properties.Authorizer.
  #
  # We support REQUEST (Lambda) authorizers only. The authorizer's Lambda is
  # referenced via FunctionArn / FunctionInvokeArn — typically a !GetAtt/!Ref to a
  # Function defined in the same template. The preprocessor resolves !GetAtt
  # "<LogicalId>.Arn" to a string ARN; we recover the template logical ID from that
  # ARN's trailing :function:<name> segment so the v2 file can map it to
  # aws_lambda_function.functions[<logicalId>]. If the ARN's function name does not
  # match a template logical ID (e.g. an explicit FunctionName or an external Lambda)
  # we fall back to the raw value and emit no managed permission for it.
  #
  # Structural source (sam_structure): authorizer NAMES feed for_each keys, so they
  # must be plan-known. Authorizer VALUES (uri etc.) are derived downstream from the
  # resolved functions map.
  #
  # ASSUMPTION: the authorizer FunctionArn/FunctionInvokeArn resolves to one of the
  # template's Function logical IDs (the common SAM pattern). Authorizers whose lambda
  # cannot be mapped to a template function are still emitted but reference the raw
  # function key, which is reported by validation if it is not a known function.
  sam_http_api_authorizers_raw = var.config_format == "sam" && local.sam_structure != null ? merge(
    try(local.sam_structure.Globals.HttpApi.Auth.Authorizers, {}),
    merge([
      for logical_id, resource in try(local.sam_structure.Resources, {}) :
      try(resource.Properties.Auth.Authorizers, {})
      if try(resource.Type, "") == "AWS::Serverless::HttpApi"
    ]...)
  ) : {}

  # Normalised authorizer definitions, keyed by authorizer name.
  #   function_ref : template Function logical ID (preferred) or raw arn/ref string
  #   api_id       : shared API id this authorizer attaches to (from DefaultAuthorizer
  #                  host resource ApiId, or any v2 event that uses this authorizer)
  #   identity_sources, result_ttl : passthrough with SAM-compatible defaults
  sam_http_api_authorizers = {
    for auth_name, auth_def in local.sam_http_api_authorizers_raw :
    auth_name => {
      # Prefer the trailing function name of a resolved Lambda ARN
      # (arn:...:function:<name>); fall back to the raw FunctionArn/FunctionInvokeArn.
      function_ref = try(
        element(split(":", tostring(try(auth_def.FunctionArn, auth_def.FunctionInvokeArn))), length(split(":", tostring(try(auth_def.FunctionArn, auth_def.FunctionInvokeArn)))) - 1),
        tostring(try(auth_def.FunctionArn, auth_def.FunctionInvokeArn, ""))
      )
      identity_sources = try(
        tolist(auth_def.Identity.Headers) != null ? [for h in tolist(auth_def.Identity.Headers) : "$request.header.${h}"] : null,
        ["$request.header.Authorization"]
      )
      enable_simple_responses = try(auth_def.EnableSimpleResponses, true)
      result_ttl              = try(auth_def.AuthorizerResultTtlInSeconds, auth_def.ResultTtlInSeconds, 0)
    }
  }

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
        # `type` distinguishes v1 REST (Api) from v2 HTTP (HttpApi). `apiId`,
        # when present on an HttpApi event, targets an EXISTING/shared
        # apigatewayv2 API (attach-only mode) instead of self-creating a REST
        # API; locals.tf routes those events to http-api-v2.tf. `authorizer`
        # is the name of a SAM HttpApi authorizer (resolved in locals.tf).
        contains(["Api", "HttpApi"], try(event.Type, "")) ? jsonencode({
          http = {
            path                 = try(event.Properties.Path, "/")
            method               = lower(try(event.Properties.Method, "any"))
            type                 = try(event.Type, "")
            apiId                = try(event.Properties.ApiId, null)
            payloadFormatVersion = try(event.Properties.PayloadFormatVersion, "2.0")
            # SAM nests the authorizer name under Properties.Auth.Authorizer; some
            # templates put it directly under Properties.Authorizer. Accept both.
            authorizer = try(event.Properties.Auth.Authorizer, event.Properties.Authorizer, null)
          }
        }) :

        # S3 → s3 (always marked existing=true since SAM S3 events reference buckets
        # that are created either via the Resources section or pre-existing)
        try(event.Type, "") == "S3" ? jsonencode({
          s3 = {
            # Bucket may be a !Ref to a template AWS::S3::Bucket — which the
            # preprocessor leaves as "__UNRESOLVED__!Ref <LogicalId>". Strip the
            # marker so the logical ID resolves to the bucket's real name; a
            # literal bucket name simply misses the lookup and is used as-is.
            bucket = try(
              local.sam_s3_bucket_names[replace(tostring(event.Properties.Bucket), local._unresolved_ref_prefix, "")],
              lower(replace(tostring(try(event.Properties.Bucket, event_name)), local._unresolved_ref_prefix, ""))
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

  # JSON-laundered to the dynamic `any` type. Two levels of laundering are needed:
  # (1) per-value, so the SimpleTable-translation branch and the pass-through
  # `resource` branch unify; and (2) the WHOLE map, so a template with
  # heterogeneously-shaped resources (e.g. ApiGatewayV2 Api + Route + Integration
  # alongside S3/DynamoDB) does not produce a concrete object type that fails to
  # unify with the empty-map `: {}` branch. Same idiom as
  # sam_custom_resources_structure below.
  sam_resources_translated = jsondecode(
    var.config_format == "sam" && local.sam_raw != null ? jsonencode({
      for logical_id, resource in try(local.sam_raw.Resources, {}) :
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
      # - Api / HttpApi → route table handled via http events on functions
      # - LayerVersion and Application → not yet supported, excluded silently
      if !contains(
        ["AWS::Serverless::Function", "AWS::Serverless::Api", "AWS::Serverless::HttpApi", "AWS::Serverless::LayerVersion", "AWS::Serverless::Application"],
        try(resource.Type, "")
      )
    }) : jsonencode({})
  )

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
        ["AWS::Serverless::Function", "AWS::Serverless::Api", "AWS::Serverless::HttpApi", "AWS::Serverless::LayerVersion", "AWS::Serverless::Application"],
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

        # Explicit execution role (SAM `Role` property, a resolved ARN). When
        # present the module honors it instead of creating a per-function role.
        role = try(tostring(resource.Properties.Role), null)

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
