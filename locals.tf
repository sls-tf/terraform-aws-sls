locals {
  # File reading with error handling
  file_content = try(
    file(var.config_path),
    null
  )

  # Configuration parsing with YAML and TypeScript support
  parsed_config = var.config_format == "yaml" ? try(
    yamldecode(local.file_content),
    null
  ) : var.config_format == "typescript" ? local.parsed_config_with_typescript : null

  # Variable Resolution Integration (Feature #11)
  # The resolved_config from variable_resolution.tf contains the parsed config
  # with all ${self:} and ${env:} variables resolved. For backward compatibility
  # and to enable variable resolution transparently, we use resolved_config
  # throughout the module by referencing it via parsed_config_resolved.
  # Note: parsed_config continues to exist for the resolution engine itself.
  parsed_config_resolved = try(local.resolved_config, local.parsed_config)

  # Comprehensive validation error collection
  validation_errors = local.parsed_config == null ? [] : concat(
    # Required field validations
    try(local.parsed_config.service, null) == null || try(local.parsed_config.service, "") == "" ?
    ["Required field 'service' is missing or empty. Specify service name in serverless.yml."] : [],

    try(local.parsed_config.provider, null) == null ?
    ["Required field 'provider' is missing. Add provider configuration in serverless.yml."] : [],

    try(local.parsed_config.provider.name, null) != "aws" ?
    ["Required field 'provider.name' must be 'aws', got: '${try(local.parsed_config.provider.name, "none")}'."] : [],

    # Strict runtime validation
    local.parsed_config != null ? local.runtime_validation_errors : [],

    # Optional provider field validations
    local.parsed_config != null ? local.provider_field_errors : [],

    # Function-level validations
    local.parsed_config != null ? local.function_validation_errors : [],

    # IAM statement validations (Roadmap #3)
    local.parsed_config != null ? local.provider_iam_validation_errors : [],
    local.parsed_config != null ? local.iam_validation_errors : [],

    # HTTP event validations (Roadmap #4)
    local.parsed_config != null ? local.http_event_validation_errors : [],

    # S3 event validations (Roadmap #5)
    local.parsed_config != null ? local.all_s3_validations : [],

    # Event source mapping validations (Roadmap #8)
    local.parsed_config != null ? local.event_source_validation_errors : [],

    # Custom resource validations (Roadmap #9)
    local.parsed_config != null ? local.custom_resource_validation_errors : [],

    # Variable resolution errors (Roadmap #11)
    local.parsed_config != null ? local.variable_resolution_errors : [],

    # TypeScript parsing errors (Roadmap #6)
    var.config_format == "typescript" ? local.typescript_all_errors : []
  )

  # Runtime validation errors (strict mode)
  runtime_validation_errors = try(local.parsed_config.provider.runtime, null) == null && try(local.parsed_config.functions, null) != null ? flatten([
    for func_name, func in try(local.parsed_config.functions, {}) :
    try(func.runtime, null) == null ?
    ["Function '${func_name}' missing required 'runtime' field. Either set provider.runtime or specify runtime for each function."] : []
  ]) : []

  # Provider field validation errors
  provider_field_errors = concat(
    # Validate frameworkVersion if specified
    try(local.parsed_config.frameworkVersion, null) != null &&
    !can(regex("^[234](\\..*)?$", local.parsed_config.frameworkVersion)) ?
    ["Field 'frameworkVersion' must be 2.x, 3.x, or 4.x, got: '${local.parsed_config.frameworkVersion}'."] : [],

    # Validate provider.memorySize range
    try(local.parsed_config.provider.memorySize, null) != null &&
    (local.parsed_config.provider.memorySize < 128 || local.parsed_config.provider.memorySize > 10240) ?
    ["Field 'provider.memorySize' must be between 128 and 10240 MB, got: ${local.parsed_config.provider.memorySize}."] : [],

    # Validate provider.timeout range
    try(local.parsed_config.provider.timeout, null) != null &&
    (local.parsed_config.provider.timeout < 1 || local.parsed_config.provider.timeout > 900) ?
    ["Field 'provider.timeout' must be between 1 and 900 seconds, got: ${local.parsed_config.provider.timeout}."] : []
  )

  # Function-level validation errors
  function_validation_errors = flatten([
    for func_name, func in try(local.parsed_config.functions, {}) : concat(
      # Validate required handler field
      try(func.handler, null) == null ?
      ["Function '${func_name}' missing required 'handler' field."] : [],

      # Validate function memorySize range
      try(func.memorySize, null) != null &&
      (func.memorySize < 128 || func.memorySize > 10240) ?
      ["Function '${func_name}' has invalid 'memorySize'. Must be between 128 and 10240 MB, got: ${func.memorySize}."] : [],

      # Validate function timeout range
      try(func.timeout, null) != null &&
      (func.timeout < 1 || func.timeout > 900) ?
      ["Function '${func_name}' has invalid 'timeout'. Must be between 1 and 900 seconds, got: ${func.timeout}."] : []
    )
  ])

  # Provider-level IAM validation errors (Roadmap #3)
  provider_iam_validation_errors = try(local.parsed_config.provider.iamRoleStatements, null) != null ? flatten([
    for idx, stmt in local.parsed_config.provider.iamRoleStatements : concat(
      # Validate Effect field
      !contains(["Allow", "Deny"], try(stmt.Effect, "")) ?
      ["Provider iamRoleStatement[${idx}]: Effect must be 'Allow' or 'Deny', got '${try(stmt.Effect, "none")}'."] : [],

      # Validate Action field exists
      try(stmt.Action, null) == null ?
      ["Provider iamRoleStatement[${idx}]: Required field 'Action' is missing."] : [],

      # Validate Resource field exists
      try(stmt.Resource, null) == null ?
      ["Provider iamRoleStatement[${idx}]: Required field 'Resource' is missing."] : [],

      # Validate Action format (service:action pattern)
      try(stmt.Action, null) != null ? flatten([
        for act in try(tolist(stmt.Action), [stmt.Action]) :
        !can(regex("^[a-z0-9]+:[*a-zA-Z0-9]+$", act)) ?
        ["Provider iamRoleStatement[${idx}]: Invalid action format '${act}'. Must match 'service:action' pattern."] : []
      ]) : []
    )
  ]) : []

  # Function-level IAM validation errors (Roadmap #3)
  iam_validation_errors = flatten([
    for func_name, func in try(local.parsed_config.functions, {}) :
    try(func.iamRoleStatements, null) != null ? flatten([
      for idx, stmt in func.iamRoleStatements : concat(
        # Validate Effect field
        !contains(["Allow", "Deny"], try(stmt.Effect, "")) ?
        ["Function '${func_name}' iamRoleStatement[${idx}]: Effect must be 'Allow' or 'Deny', got '${try(stmt.Effect, "none")}'."] : [],

        # Validate Action field exists
        try(stmt.Action, null) == null ?
        ["Function '${func_name}' iamRoleStatement[${idx}]: Required field 'Action' is missing."] : [],

        # Validate Resource field exists
        try(stmt.Resource, null) == null ?
        ["Function '${func_name}' iamRoleStatement[${idx}]: Required field 'Resource' is missing."] : [],

        # Validate Action format (service:action pattern)
        try(stmt.Action, null) != null ? flatten([
          for act in try(tolist(stmt.Action), [stmt.Action]) :
          !can(regex("^[a-z0-9]+:[*a-zA-Z0-9]+$", act)) ?
          ["Function '${func_name}' iamRoleStatement[${idx}]: Invalid action format '${act}'. Must match 'service:action' pattern."] : []
        ]) : []
      )
    ]) : []
  ])

  # Provider-level defaults application
  provider_with_defaults = local.parsed_config_resolved == null ? null : merge(
    try(local.parsed_config_resolved.provider, {}),
    {
      stage      = coalesce(try(local.parsed_config_resolved.provider.stage, null), "dev")
      region     = coalesce(try(local.parsed_config_resolved.provider.region, null), var.aws_region, "us-east-1")
      memorySize = coalesce(try(local.parsed_config_resolved.provider.memorySize, null), 1024)
      timeout    = coalesce(try(local.parsed_config_resolved.provider.timeout, null), 6)
      # Runtime has NO default - must be explicitly specified (strict validation)
    }
  )

  # Function-level default inheritance (before validation)
  # Used for parsing events - cannot depend on validation_errors
  functions_with_defaults_prevalidation = {
    for func_name, func in try(local.parsed_config.functions, {}) :
    func_name => merge(func, {
      runtime    = try(coalesce(try(func.runtime, null), try(local.parsed_config.provider.runtime, null)), null)
      memorySize = coalesce(try(func.memorySize, null), local.provider_with_defaults.memorySize)
      timeout    = coalesce(try(func.timeout, null), local.provider_with_defaults.timeout)
    })
  }

  # Function-level default inheritance (after validation)
  # Used for resource generation - filters out invalid configs
  functions_with_defaults = {
    for func_name, func in local.functions_with_defaults_prevalidation :
    func_name => func
    if length(local.validation_errors) == 0
  }

  # Region override warning
  region_warnings = (
    var.aws_region != null &&
    try(local.parsed_config.provider.region, null) != null &&
    var.aws_region != local.parsed_config.provider.region
    ) ? [
    "WARNING: aws_region override '${var.aws_region}' differs from serverless.yml region '${local.parsed_config.provider.region}'. Using override value."
  ] : []

  # IAM Role Statement Parsing (Roadmap #3)
  # Provider-level iamRoleStatements
  provider_iam_statements = try(local.parsed_config.provider.iamRoleStatements, [])

  # Normalize provider-level statements (Action/Resource: string -> array)
  provider_iam_statements_normalized = [
    for stmt in local.provider_iam_statements :
    merge(stmt, {
      Action   = try(tolist(stmt.Action), [stmt.Action])
      Resource = try(tolist(stmt.Resource), [stmt.Resource])
    })
  ]

  # Function-level iamRoleStatements (map of function_name -> statements)
  function_iam_statements = {
    for func_name, func in local.functions_with_defaults_prevalidation :
    func_name => try(func.iamRoleStatements, [])
  }

  # Normalize function-level statements (Action/Resource: string -> array)
  function_iam_statements_normalized = {
    for func_name, stmts in local.function_iam_statements :
    func_name => [
      for stmt in stmts :
      merge(stmt, {
        Action   = try(tolist(stmt.Action), [stmt.Action])
        Resource = try(tolist(stmt.Resource), [stmt.Resource])
      })
    ]
  }

  # Merge provider and function statements per function
  merged_iam_statements = {
    for func_name, func in local.functions_with_defaults_prevalidation :
    func_name => concat(
      local.provider_iam_statements_normalized,
      local.function_iam_statements_normalized[func_name]
    )
  }

  # Functions requiring custom policies (non-empty statements)
  functions_with_policies = {
    for func_name, statements in local.merged_iam_statements :
    func_name => statements
    if length(statements) > 0
  }

  # HTTP Event Parsing (Roadmap #4)
  # Extract all HTTP events from all functions
  # Use prevalidation version to avoid circular dependency
  http_events = flatten([
    for func_name, func in local.functions_with_defaults_prevalidation : [
      for event in try(func.events, []) :
      merge({
        function_name = func_name
        handler       = tostring(func.handler)
        runtime       = tostring(func.runtime)
        http_method   = ""
        http_path     = ""
        cors_enabled  = false
        cors_config = {
          origin  = null
          headers = null
        }
        }, {
        # Parse short-form: "http: GET /users/{id}"
        # Parse long-form: "http: { path: /users, method: GET, cors: true }"
        http_method = (can(event.http) && can(regex("^[A-Z]+ ", tostring(event.http)))) ? upper(split(" ", tostring(event.http))[0]) : upper(try(event.http.method, ""))

        http_path = (can(event.http) && can(regex("^[A-Z]+ ", tostring(event.http)))) ? trimprefix(trimsuffix(trimspace(substr(tostring(event.http), length(split(" ", tostring(event.http))[0]) + 1, -1)), "/"), "") : trimsuffix(try(event.http.path, ""), "/")

        cors_enabled = can(event.http.cors) ? (can(tobool(event.http.cors)) ? tobool(event.http.cors) : true) : false

        # Always use map type for cors_config to ensure type consistency
        cors_config = (can(event.http.cors) && !can(tobool(event.http.cors))) ? {
          origin  = try(event.http.cors.origin, null)
          headers = try(event.http.cors.headers, null)
          } : {
          origin  = null
          headers = null
        }
      })
      if can(event.http)
    ]
  ])

  # Deduplicate functions with HTTP events for permissions
  functions_with_http_events = toset([
    for event in local.http_events : event.function_name
  ])

  # HTTP event validation errors
  http_event_validation_errors = flatten([
    for event in local.http_events : concat(
      # Validate HTTP method
      !contains(["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"], event.http_method) ?
      ["Function '${event.function_name}' has invalid HTTP method '${event.http_method}'. Must be one of: GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS."] : [],

      # Validate path starts with /
      !can(regex("^/", event.http_path)) ?
      ["Function '${event.function_name}' has invalid HTTP path '${event.http_path}'. Path must start with '/'."] : [],

      # Validate no empty segments
      can(regex("//", event.http_path)) ?
      ["Function '${event.function_name}' has invalid HTTP path '${event.http_path}'. Path cannot contain empty segments (consecutive slashes)."] : [],

      # Validate path parameters
      can(regex("\\{[^a-zA-Z0-9_]", event.http_path)) || can(regex("\\{\\}", event.http_path)) ?
      ["Function '${event.function_name}' has invalid path parameter syntax in '${event.http_path}'. Parameters must be {paramName} with alphanumeric/underscore characters only."] : []
    )
  ])

  # Path Parsing and Resource Tree Building (Phase 2)
  # Extract unique paths from HTTP events
  all_paths = toset([
    for event in local.http_events : event.http_path
  ])

  # Parse each path into array of segments
  path_segments = {
    for path in local.all_paths :
    path => split("/", trimprefix(path, "/"))
  }

  # Build complete set of intermediate paths
  # Example: /users/{id}/posts generates ["/users", "/users/{id}", "/users/{id}/posts"]
  all_resource_paths = toset(flatten([
    for path in local.all_paths : [
      for i in range(1, length(local.path_segments[path]) + 1) :
      "/${join("/", slice(local.path_segments[path], 0, i))}"
    ]
  ]))

  # Build resource tree with metadata
  resource_tree = {
    for path in local.all_resource_paths :
    path => {
      segments    = split("/", trimprefix(path, "/"))
      depth       = length(split("/", trimprefix(path, "/")))
      path_part   = split("/", trimprefix(path, "/"))[length(split("/", trimprefix(path, "/"))) - 1]
      parent_path = length(split("/", trimprefix(path, "/"))) > 1 ? "/${join("/", slice(split("/", trimprefix(path, "/")), 0, length(split("/", trimprefix(path, "/"))) - 1))}" : null
      # Sanitize resource name for Terraform identifiers
      resource_name = replace(replace(replace(path, "/", "_"), "{", ""), "}", "")
    }
  }

  # CORS Configuration Builder (Phase 3)
  # Serverless Framework default CORS values
  cors_defaults = {
    origin           = "*"
    headers          = ["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key", "X-Amz-Security-Token", "X-Amz-User-Agent"]
    allowCredentials = false
  }

  # Build CORS configuration per resource path
  # Aggregate all methods and CORS configs for each path
  resource_cors_config = {
    for path in local.all_resource_paths :
    path => {
      # Check if any event on this path has CORS enabled
      enabled = anytrue([
        for event in local.http_events :
        event.http_path == path && event.cors_enabled
      ])
      # Collect all methods on this path
      methods = distinct([
        for event in local.http_events :
        event.http_method if event.http_path == path
      ])
      # Merge custom CORS configs (take first non-null custom config if any)
      custom_config = try(
        [
          for event in local.http_events :
          event.cors_config if event.http_path == path && event.cors_config.origin != null
        ][0],
        {
          origin  = null
          headers = null
        }
      )
    }
  }

  # Format CORS headers for API Gateway integration response
  # Only include CORS-enabled resources
  cors_headers = {
    for path, config in local.resource_cors_config :
    path => {
      "Access-Control-Allow-Origin"  = "'${config.custom_config.origin != null ? config.custom_config.origin : local.cors_defaults.origin}'"
      "Access-Control-Allow-Headers" = "'${join(",", config.custom_config.headers != null ? config.custom_config.headers : local.cors_defaults.headers)}'"
      "Access-Control-Allow-Methods" = "'${join(",", concat(config.methods, ["OPTIONS"]))}'"
    }
    if config.enabled
  }

  # Resource tree grouped by depth to avoid cycles in API Gateway resource creation
  # This allows us to create resources level by level
  max_depth = length(local.all_resource_paths) > 0 ? max([for path, meta in local.resource_tree : meta.depth]...) : 0

  resources_by_depth = {
    for depth in range(1, local.max_depth + 1) :
    depth => {
      for path, meta in local.resource_tree :
      path => meta
      if meta.depth == depth
    }
  }

  # S3 Event Parsing (Roadmap #5)
  # Extract all S3 events from all functions
  s3_events_raw = flatten([
    for func_name, func in local.functions_with_defaults_prevalidation : [
      for idx, event in try(func.events, []) :
      try(event.s3, null) != null ? {
        function_name = func_name
        event_index   = idx
        s3_config     = event.s3
      } : null
    ]
  ])

  # Normalize both shorthand and object syntax to consistent format
  s3_events_normalized = [
    for evt in local.s3_events_raw :
    evt != null ? {
      function_name = evt.function_name
      event_index   = evt.event_index
      # Bucket key is either object.bucket or string value
      # Use tostring() to handle both string and object cases
      bucket_key = try(evt.s3_config.bucket, tostring(evt.s3_config))
      # Bucket name resolved from custom properties or bucket key
      bucket_name = try(
        local.s3_buckets_custom_properties[try(evt.s3_config.bucket, tostring(evt.s3_config))].name,
        try(evt.s3_config.bucket, tostring(evt.s3_config))
      )
      # Event type defaults to s3:ObjectCreated:*
      event_type = try(evt.s3_config.event, "s3:ObjectCreated:*")
      # Rules array (prefix/suffix filters)
      rules = try(evt.s3_config.rules, [])
      # Existing bucket flag (default false)
      existing = try(evt.s3_config.existing, false)
      # Force deploy flag (default false)
      force_deploy = try(evt.s3_config.forceDeploy, false)
    } : null
    if evt != null
  ]

  # Parse custom bucket properties from provider.s3 section
  s3_buckets_custom_properties = try(local.parsed_config.provider.s3, {})

  # Identify unique buckets that need to be created (not existing)
  s3_buckets_to_create = {
    for bucket_key in distinct([
      for evt in local.s3_events_normalized :
      evt.bucket_key if !evt.existing
    ]) :
    bucket_key => {
      name       = try(local.s3_buckets_custom_properties[bucket_key].name, bucket_key)
      properties = try(local.s3_buckets_custom_properties[bucket_key], {})
    }
  }

  # S3 Event Validation (Roadmap #5)
  # S3 event configuration validation errors
  s3_event_validations = flatten([
    for evt in local.s3_events_normalized : concat(
      # Validate bucket name not empty
      evt.bucket_name == "" ?
      ["Function '${evt.function_name}' S3 event[${evt.event_index}]: Bucket name is required."] : [],

      # Validate event type is valid S3 event
      !contains([
        "s3:ObjectCreated:*", "s3:ObjectCreated:Put", "s3:ObjectCreated:Post",
        "s3:ObjectCreated:Copy", "s3:ObjectCreated:CompleteMultipartUpload",
        "s3:ObjectRemoved:*", "s3:ObjectRemoved:Delete", "s3:ObjectRemoved:DeleteMarkerCreated",
        "s3:ObjectRestore:*", "s3:ObjectRestore:Post", "s3:ObjectRestore:Completed",
        "s3:ReducedRedundancyLostObject", "s3:Replication:*"
      ], evt.event_type) ?
      ["Function '${evt.function_name}' S3 event[${evt.event_index}]: Invalid event type '${evt.event_type}'."] : [],

      # Validate forceDeploy only with existing
      evt.force_deploy && !evt.existing ?
      ["Function '${evt.function_name}' S3 event[${evt.event_index}]: forceDeploy can only be used with existing: true."] : [],

      # Validate S3 bucket naming conventions
      !can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", evt.bucket_name)) ?
      ["Function '${evt.function_name}' S3 event[${evt.event_index}]: Bucket name '${evt.bucket_name}' violates S3 naming conventions."] : []
    )
  ])

  # Aggregate S3 notifications for duplicate detection
  s3_notifications_aggregated = {
    for bucket_name in distinct([for evt in local.s3_events_normalized : evt.bucket_name]) :
    bucket_name => [
      for evt in local.s3_events_normalized :
      {
        function_name = evt.function_name
        events        = [evt.event_type]
        filter_prefix = try([for rule in evt.rules : rule.prefix if try(rule.prefix, null) != null][0], null)
        filter_suffix = try([for rule in evt.rules : rule.suffix if try(rule.suffix, null) != null][0], null)
      }
      if evt.bucket_name == bucket_name
    ]
  }

  # Detect duplicate event configurations (same bucket + event type + filter rules)
  s3_duplicate_validations = [
    for bucket_name, events in local.s3_notifications_aggregated :
    length(events) != length(distinct([
      for evt in events :
      "${evt.events[0]}-${evt.filter_prefix != null ? evt.filter_prefix : ""}-${evt.filter_suffix != null ? evt.filter_suffix : ""}"
    ])) ?
    "Bucket '${bucket_name}' has duplicate event configurations. Each function must have unique event type or filter rules." : null
  ]

  # Combine all S3 validations
  all_s3_validations = concat(
    local.s3_event_validations,
    [for err in local.s3_duplicate_validations : err if err != null]
  )

  # DynamoDB & SQS Event Source Mapping (Roadmap #8)
  # Flatten nested function/events structure into flat map for for_each
  event_source_mappings = merge([
    for func_name, func in local.functions_with_defaults_prevalidation : {
      for idx, event in try(func.events, []) :
      # Create unique identifier: {function}_{type}_{index}
      "${func_name}_${try(event.stream, null) != null ? "stream" : "sqs"}_${idx}" => {
        function_name = func_name
        event_index   = idx
        # Detect event type by checking for stream or sqs fields
        type = try(event.stream, null) != null ? "stream" : (
          try(event.sqs, null) != null ? "sqs" : null
        )
        # Extract event configuration
        event_config = try(event.stream, null) != null ? event.stream : (
          try(event.sqs, null) != null ? event.sqs : null
        )
        # Extract ARN from either stream.arn or sqs.arn or sqs itself (shorthand)
        arn = try(event.stream, null) != null ? (
          try(event.stream.arn, tostring(event.stream))
          ) : (
          try(event.sqs.arn, tostring(event.sqs))
        )
        # Detect FIFO queue by .fifo suffix in ARN
        is_fifo_queue = try(event.sqs, null) != null && can(regex("\\.fifo$", try(event.sqs.arn, tostring(event.sqs))))
      }
      # Only include DynamoDB stream and SQS events
      if(try(event.stream, null) != null || try(event.sqs, null) != null)
    }
  ]...)

  # Event Source Mapping Validation (Roadmap #8)
  event_source_validation_errors = flatten([
    for key, mapping in local.event_source_mappings : concat(
      # Validate batch size based on event type
      mapping.type == "stream" && try(mapping.event_config.batchSize, null) != null &&
      (mapping.event_config.batchSize < 1 || mapping.event_config.batchSize > 10000) ?
      ["Function '${mapping.function_name}' event[${mapping.event_index}]: DynamoDB stream batchSize must be between 1 and 10000, got ${mapping.event_config.batchSize}."] : [],

      # Validate SQS standard queue batch size (1-10)
      mapping.type == "sqs" && !mapping.is_fifo_queue && try(mapping.event_config.batchSize, null) != null &&
      (mapping.event_config.batchSize < 1 || mapping.event_config.batchSize > 10) ?
      ["Function '${mapping.function_name}' event[${mapping.event_index}]: SQS standard queue batchSize must be between 1 and 10, got ${mapping.event_config.batchSize}."] : [],

      # Validate SQS FIFO queue batch size (1-10000)
      mapping.type == "sqs" && mapping.is_fifo_queue && try(mapping.event_config.batchSize, null) != null &&
      (mapping.event_config.batchSize < 1 || mapping.event_config.batchSize > 10000) ?
      ["Function '${mapping.function_name}' event[${mapping.event_index}]: SQS FIFO queue batchSize must be between 1 and 10000, got ${mapping.event_config.batchSize}."] : [],

      # Validate starting position for DynamoDB streams
      mapping.type == "stream" && try(mapping.event_config.startingPosition, null) != null &&
      !contains(["LATEST", "TRIM_HORIZON"], mapping.event_config.startingPosition) ?
      ["Function '${mapping.function_name}' event[${mapping.event_index}]: startingPosition must be 'LATEST' or 'TRIM_HORIZON', got '${mapping.event_config.startingPosition}'."] : [],

      # Validate DynamoDB stream ARN format
      mapping.type == "stream" && !can(regex("^arn:aws:dynamodb:[^:]+:[^:]+:table/[^/]+/stream/.+$", mapping.arn)) ?
      ["Function '${mapping.function_name}' event[${mapping.event_index}]: Invalid DynamoDB stream ARN format. Expected pattern: arn:aws:dynamodb:region:account:table/TableName/stream/StreamLabel"] : [],

      # Validate SQS queue ARN format
      mapping.type == "sqs" && !can(regex("^arn:aws:sqs:[^:]+:[^:]+:.+$", mapping.arn)) ?
      ["Function '${mapping.function_name}' event[${mapping.event_index}]: Invalid SQS queue ARN format. Expected pattern: arn:aws:sqs:region:account:QueueName"] : [],

      # Validate maximum_retry_attempts range (0-10000)
      try(mapping.event_config.maximumRetryAttempts, null) != null &&
      (mapping.event_config.maximumRetryAttempts < 0 || mapping.event_config.maximumRetryAttempts > 10000) ?
      ["Function '${mapping.function_name}' event[${mapping.event_index}]: maximumRetryAttempts must be between 0 and 10000, got ${mapping.event_config.maximumRetryAttempts}."] : [],

      # Validate parallelization_factor range (1-10, DynamoDB only)
      mapping.type == "stream" && try(mapping.event_config.parallelizationFactor, null) != null &&
      (mapping.event_config.parallelizationFactor < 1 || mapping.event_config.parallelizationFactor > 10) ?
      ["Function '${mapping.function_name}' event[${mapping.event_index}]: parallelizationFactor must be between 1 and 10, got ${mapping.event_config.parallelizationFactor}."] : [],

      # Validate maximum_batching_window_in_seconds range (0-300)
      try(mapping.event_config.maximumBatchingWindowInSeconds, null) != null &&
      (mapping.event_config.maximumBatchingWindowInSeconds < 0 || mapping.event_config.maximumBatchingWindowInSeconds > 300) ?
      ["Function '${mapping.function_name}' event[${mapping.event_index}]: maximumBatchingWindowInSeconds must be between 0 and 300, got ${mapping.event_config.maximumBatchingWindowInSeconds}."] : [],

      # Validate tumbling_window_in_seconds range (0-900, DynamoDB only)
      mapping.type == "stream" && try(mapping.event_config.tumblingWindowInSeconds, null) != null &&
      (mapping.event_config.tumblingWindowInSeconds < 0 || mapping.event_config.tumblingWindowInSeconds > 900) ?
      ["Function '${mapping.function_name}' event[${mapping.event_index}]: tumblingWindowInSeconds must be between 0 and 900, got ${mapping.event_config.tumblingWindowInSeconds}."] : []
    )
  ])

  # IAM permissions for event source mappings (Roadmap #8)
  # Generate required permissions for DynamoDB streams and SQS queues
  event_source_iam_statements = concat(
    # DynamoDB stream read permissions
    length([for k, v in local.event_source_mappings : k if v.type == "stream"]) > 0 ? [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:DescribeStream",
          "dynamodb:ListStreams"
        ]
        Resource = distinct([for k, v in local.event_source_mappings : v.arn if v.type == "stream"])
      }
    ] : [],
    # SQS queue consume permissions
    length([for k, v in local.event_source_mappings : k if v.type == "sqs"]) > 0 ? [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = distinct([for k, v in local.event_source_mappings : v.arn if v.type == "sqs"])
      }
    ] : []
  )

  # ============================================================================
  # EventBridge & Schedule Event Parsing (Roadmap #7)
  # ============================================================================

  # Flatten schedule events from all functions
  # Schedule events support both string syntax (schedule: "rate(5 minutes)")
  # and object syntax (schedule: { rate: "...", enabled: false, ... })
  all_schedule_events = flatten([
    for func_name, func in local.functions_with_defaults : [
      for event_idx, event in try(func.events, []) : {
        function_name = func_name
        event_index   = event_idx
        event_key     = "${func_name}-schedule-${event_idx}"
        # Handle string syntax: schedule: "rate(5 minutes)"
        # Handle object syntax: schedule: { rate: "cron(...)", enabled: false }
        schedule_expression = (
          can(event.schedule.rate) ? event.schedule.rate :
          can(event.schedule.cron) ? event.schedule.cron :
          tostring(event.schedule)
        )
        enabled          = can(event.schedule.enabled) ? event.schedule.enabled : try(event.enabled, true)
        description      = can(event.schedule.description) ? event.schedule.description : try(event.description, null)
        input            = can(event.schedule.input) ? event.schedule.input : try(event.input, null)
        inputPath        = can(event.schedule.inputPath) ? event.schedule.inputPath : try(event.inputPath, null)
        inputTransformer = can(event.schedule.inputTransformer) ? event.schedule.inputTransformer : try(event.inputTransformer, null)
      } if can(event.schedule)
    ]
  ])

  # Create map for for_each iteration
  schedule_event_map = {
    for event in local.all_schedule_events :
    event.event_key => event
  }

  # Flatten eventBridge events from all functions
  # EventBridge events support event patterns and custom event buses
  all_eventbridge_events = flatten([
    for func_name, func in local.functions_with_defaults : [
      for event_idx, event in try(func.events, []) : {
        function_name    = func_name
        event_index      = event_idx
        event_key        = "${func_name}-eventbridge-${event_idx}"
        pattern          = try(event.eventBridge.pattern, {})
        eventBus         = try(event.eventBridge.eventBus, "default")
        enabled          = try(event.eventBridge.enabled, true)
        description      = try(event.eventBridge.description, null)
        input            = try(event.eventBridge.input, null)
        inputPath        = try(event.eventBridge.inputPath, null)
        inputTransformer = try(event.eventBridge.inputTransformer, null)
      } if can(event.eventBridge)
    ]
  ])

  # Create map for for_each iteration
  eventbridge_event_map = {
    for event in local.all_eventbridge_events :
    event.event_key => event
  }

  # ============================================================================
  # Custom Resource Parsing (Roadmap #9)
  # ============================================================================

  # Extract resources section from serverless config (with variable resolution)
  custom_resources_raw = try(local.resolved_config.resources.Resources, {})

  # Helper function to convert PascalCase to snake_case
  # Example: MyBucket -> my_bucket, UsersTable -> users_table
  # Terraform replace() doesn't support capture groups well, so we use a simple approach
  to_snake_case = {
    for logical_id, resource in local.custom_resources_raw :
    logical_id => lower(join("_", regexall("[A-Z][a-z0-9]*", logical_id)))
  }

  # Categorize resources by type
  s3_buckets = {
    for logical_id, resource in local.custom_resources_raw :
    logical_id => resource
    if try(resource.Type, "") == "AWS::S3::Bucket"
  }

  dynamodb_tables = {
    for logical_id, resource in local.custom_resources_raw :
    logical_id => resource
    if try(resource.Type, "") == "AWS::DynamoDB::Table"
  }

  sns_topics = {
    for logical_id, resource in local.custom_resources_raw :
    logical_id => resource
    if try(resource.Type, "") == "AWS::SNS::Topic"
  }

  sqs_queues = {
    for logical_id, resource in local.custom_resources_raw :
    logical_id => resource
    if try(resource.Type, "") == "AWS::SQS::Queue"
  }

  cloudfront_distributions = {
    for logical_id, resource in local.custom_resources_raw :
    logical_id => resource
    if try(resource.Type, "") == "AWS::CloudFront::Distribution"
  }

  # Supported resource types
  supported_resource_types = toset([
    "AWS::S3::Bucket",
    "AWS::DynamoDB::Table",
    "AWS::SNS::Topic",
    "AWS::SQS::Queue",
    "AWS::CloudFront::Distribution"
  ])

  # Identify unsupported resource types for validation
  unsupported_resources = {
    for logical_id, resource in local.custom_resources_raw :
    logical_id => resource.Type
    if try(resource.Type, "") != "" && !contains(local.supported_resource_types, resource.Type)
  }

  # Validation errors for unsupported resources
  custom_resource_validation_errors = [
    for logical_id, type in local.unsupported_resources :
    "Unsupported CloudFormation resource type '${type}' for resource '${logical_id}'. Supported types: S3::Bucket, DynamoDB::Table, SNS::Topic, SQS::Queue, CloudFront::Distribution."
  ]
}
