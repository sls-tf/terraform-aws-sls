# ============================================================================
# AWS SAM Template Validation
# ============================================================================
# SAM-specific validation that runs before the standard SLS validation pipeline.
# These errors are surfaced even when YAML parsing fails (e.g. missing Transform).

locals {
  sam_validation_errors = var.config_format != "sam" ? [] : (
    # Surface preprocessor evaluation errors (e.g. unresolved !Ref in strict mode)
    # before checking sam_raw so the message is specific rather than "failed to parse".
    try(data.external.sam_yaml[0].result.error, "") != "" ? [
      "SAM template preprocessing failed: ${data.external.sam_yaml[0].result.error}"
    ] :
    local.sam_raw == null ? [
      "Failed to parse SAM template at '${var.config_path}'. Verify the file exists and is valid YAML. Run with TF_LOG=DEBUG to see preprocessor stderr."
      ] : concat(
      # Transform declaration is required and must be the SAM value
      try(local.sam_raw.Transform, null) == null ? [
        "SAM template is missing the required 'Transform: AWS::Serverless-2016-10-31' declaration."
        ] : (
        tostring(try(local.sam_raw.Transform, "")) != "AWS::Serverless-2016-10-31" ? [
          "SAM template 'Transform' must be 'AWS::Serverless-2016-10-31', got: '${tostring(local.sam_raw.Transform)}'."
        ] : []
      ),

      # Resources section is required
      try(local.sam_raw.Resources, null) == null ? [
        "SAM template is missing the required 'Resources' section."
      ] : [],

      # Each AWS::Serverless::Function must have a Handler
      flatten([
        for logical_id, resource in try(local.sam_raw.Resources, {}) :
        try(resource.Properties.Handler, null) == null ? [
          "SAM function '${logical_id}' is missing the required 'Properties.Handler' field."
        ] : []
        if try(resource.Type, "") == "AWS::Serverless::Function"
      ]),

      # Validate memory/timeout on SAM functions match Lambda limits
      flatten([
        for logical_id, resource in try(local.sam_raw.Resources, {}) : concat(
          try(resource.Properties.MemorySize, null) != null &&
          (resource.Properties.MemorySize < 128 || resource.Properties.MemorySize > 10240) ? [
            "SAM function '${logical_id}' MemorySize must be between 128 and 10240 MB, got: ${resource.Properties.MemorySize}."
          ] : [],
          try(resource.Properties.Timeout, null) != null &&
          (resource.Properties.Timeout < 1 || resource.Properties.Timeout > 900) ? [
            "SAM function '${logical_id}' Timeout must be between 1 and 900 seconds, got: ${resource.Properties.Timeout}."
          ] : []
        )
        if try(resource.Type, "") == "AWS::Serverless::Function"
      ]),

      # Fail loud on environment variables that did not resolve to a scalar.
      # After the preprocessor evaluates intrinsics, a non-scalar env value means
      # an unsupported/unresolved CloudFormation intrinsic (e.g. a !GetAtt or !If
      # the evaluator could not reduce) or a literal list/map leaked through —
      # always a bug. Without this guard the value coerces to a "<<unresolved-
      # intrinsic>>" sentinel and would deploy as a meaningless string; with it,
      # the offending function + variable name is reported explicitly.
      local.sam_env_nonscalar_errors
    )
  )

  # Per-(function, variable) errors for env values that are not scalar after
  # intrinsic evaluation. Uses the merged Globals + per-function env, matching
  # what sam-parser.tf coerces. `!can(tostring(v))` is true only for collections.
  sam_env_nonscalar_errors = var.config_format != "sam" || local.sam_raw == null ? [] : flatten([
    for logical_id, resource in try(local.sam_raw.Resources, {}) : [
      for k, v in merge(
        try(local.sam_function_globals.Environment.Variables, {}),
        try(resource.Properties.Environment.Variables, {})
      ) :
      "SAM function '${logical_id}' environment variable '${k}' did not resolve to a scalar value. An unsupported or unresolved CloudFormation intrinsic likely leaked through. Resolve it in the template, or compute the value in Terraform and pass it via sam_template_parameters."
      if !can(tostring(v))
    ]
    if try(resource.Type, "") == "AWS::Serverless::Function"
  ])
}
