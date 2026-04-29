# ============================================================================
# AWS SAM Template Parser
# ============================================================================
# Parses AWS SAM template.yaml files and translates them to the SLS-compatible
# config structure used throughout the rest of the module. All existing resource
# blocks (Lambda, API Gateway, S3, DynamoDB, SQS, etc.) consume this translated
# config without modification.

locals {
  # Raw YAML parse — only active when config_format is "sam"
  sam_raw = var.config_format == "sam" ? try(
    yamldecode(local.file_content),
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

  # Globals.Function — applied to all functions unless overridden per-function
  sam_function_globals = var.config_format == "sam" && local.sam_raw != null ? try(
    local.sam_raw.Globals.Function,
    {}
  ) : {}

  # Globals.Api — applied to all API resources
  sam_api_globals = var.config_format == "sam" && local.sam_raw != null ? try(
    local.sam_raw.Globals.Api,
    {}
  ) : {}

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
        handler     = try(resource.Properties.Handler, "index.handler")
        runtime     = try(resource.Properties.Runtime, null)
        description = try(resource.Properties.Description, null)
        memorySize  = try(resource.Properties.MemorySize, null)
        timeout     = try(resource.Properties.Timeout, null)

        # Global env vars merged with function-level env vars (function wins on conflict)
        environment = merge(
          try(local.sam_function_globals.Environment.Variables, {}),
          try(resource.Properties.Environment.Variables, {})
        )

        # Translate inline SAM policy documents to iamRoleStatements.
        # SAM managed policy names (strings) and AWS managed policy ARNs are
        # not translated here — the Lambda execution role still gets basic
        # CloudWatch Logs permissions from main.tf.
        iamRoleStatements = flatten([
          for policy in try(tolist(resource.Properties.Policies), []) :
          can(policy.Statement) ? [
            for stmt in try(tolist(policy.Statement), []) : {
              Effect   = try(stmt.Effect, "Allow")
              Action   = try(tolist(stmt.Action), [tostring(try(stmt.Action, "*"))])
              Resource = try(tolist(stmt.Resource), [tostring(try(stmt.Resource, "*"))])
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
