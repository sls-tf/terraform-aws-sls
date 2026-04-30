# ============================================================================
# AWS SAM Template Validation
# ============================================================================
# SAM-specific validation that runs before the standard SLS validation pipeline.
# These errors are surfaced even when YAML parsing fails (e.g. missing Transform).

locals {
  sam_validation_errors = var.config_format != "sam" ? [] : (
    local.sam_raw == null ? [
      try(data.external.sam_yaml[0].result.error, "") != "" ?
        "SAM YAML preprocessing failed: ${data.external.sam_yaml[0].result.error}" :
        "Failed to parse SAM template at '${var.config_path}'. Please verify the file exists and contains valid YAML syntax."
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
      ])
    )
  )
}
