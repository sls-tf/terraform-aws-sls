locals {
  # File reading with error handling
  file_content = try(
    file(var.config_path),
    null
  )

  # Configuration parsing with YAML, TypeScript, and SAM support.
  # For SAM format, nonsensitive() is applied to break the sensitivity chain from
  # external data source / resolved parameters into for_each iteration maps.
  # SAM parameter values are ARNs and config strings (visible in Lambda env vars
  # in the AWS console), not actual secrets, so this stripping is semantically correct.
  # Each format produces a differently-shaped object (a raw YAML/SAM template vs
  # the translated SLS config). A plain ternary across them raises "Inconsistent
  # conditional result types" under Terraform's structural unification, because
  # the unused yamldecode(file_content) branch infers a concrete object type from
  # the static file that cannot unify with sam_as_sls_config. Encoding every
  # branch to JSON (all `string`, so they unify) and decoding once yields a value
  # of the dynamic type `any` — which every downstream consumer already accesses
  # via try()/can(). Decoding a computed (non-literal) string is what forces the
  # `any` type and defeats the eager unification.
  _parsed_config_raw = try(jsondecode(
    var.config_format == "yaml" ? jsonencode(try(yamldecode(local.file_content), null)) :
    var.config_format == "typescript" ? jsonencode(local.parsed_config_with_typescript) :
    var.config_format == "sam" ? jsonencode(try(nonsensitive(local.sam_as_sls_config), null)) :
    "null"
  ), null)

  # Normalise `service` to a string. Serverless Framework accepts both the v3+
  # string form (`service: my-svc`) and the legacy object form
  # (`service: { name: my-svc }`); downstream naming and variable resolution
  # require a string. can(...service.name) is true only for the object form.
  # JSON-laundered to `any`: the coerced branch (service: string) and the
  # pass-through branch (service: object) are differently-shaped object types
  # that a bare ternary cannot unify. Encoding both to a string and decoding once
  # yields `any`, the same idiom used for the format dispatch above.
  parsed_config = local._parsed_config_raw == null ? null : jsondecode(
    can(local._parsed_config_raw.service.name) ?
    jsonencode(merge(local._parsed_config_raw, { service = tostring(local._parsed_config_raw.service.name) })) :
    jsonencode(local._parsed_config_raw)
  )

  # Variable Resolution Integration (Feature #11)
  # The resolved_config from variable_resolution.tf contains the parsed config
  # with all ${self:} and ${env:} variables resolved. For backward compatibility
  # and to enable variable resolution transparently, we use resolved_config
  # throughout the module by referencing it via parsed_config_resolved.
  # Note: parsed_config continues to exist for the resolution engine itself.
  # nonsensitive(): resolved_config derives from parsed_config (itself nonsensitive)
  # via purely string-substitution passes; the result carries no secret material.
  # Wrapping here prevents taint from propagating into aws_lambda_function.function_name.
  parsed_config_resolved = nonsensitive(try(local.resolved_config, local.parsed_config))

  # Comprehensive validation error collection
  # SAM errors are prepended outside the null check so parse failures are reported.
  # nonsensitive(): validation messages are plain strings, never secrets. The taint
  # arrives via parsed_config_resolved → variable_resolution.tf → resolved_config.
  validation_errors = nonsensitive(local.parsed_config == null ? (
    # parsed_config is null: a parse/read failure. Surface the format-specific
    # error (TS parser error, SAM parse error) so config_validation fails with a
    # clear message rather than a generic "Failed to parse YAML".
    var.config_format == "sam" ? local.sam_validation_errors :
    var.config_format == "typescript" ? local.typescript_all_errors : []
    ) : concat(
    # SAM-specific validation (Handler missing, Transform wrong, etc.)
    var.config_format == "sam" ? local.sam_validation_errors : [],
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

    # API Gateway v2 (HTTP API) authorizer validations
    local.parsed_config != null ? local.http_api_v2_authorizer_errors : [],

    # S3 event validations (Roadmap #5)
    local.parsed_config != null ? local.all_s3_validations : [],

    # Event source mapping validations (Roadmap #8)
    local.parsed_config != null ? local.event_source_validation_errors : [],

    # Custom resource validations (Roadmap #9)
    local.parsed_config != null ? local.custom_resource_validation_errors : [],

    # Variable resolution errors (Roadmap #11)
    local.parsed_config != null ? local.variable_resolution_errors : [],

    # CloudFront event validations (Roadmap #12)
    local.parsed_config != null ? local.cloudfront_event_validation_errors : [],

    # TypeScript parsing errors (Roadmap #6)
    var.config_format == "typescript" ? local.typescript_all_errors : []
  ))

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
        !can(regex("^[a-z0-9-]+:[*a-zA-Z0-9]+$", act)) ?
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
          !can(regex("^[a-z0-9-]+:[*a-zA-Z0-9]+$", act)) ?
          ["Function '${func_name}' iamRoleStatement[${idx}]: Invalid action format '${act}'. Must match 'service:action' pattern."] : []
        ]) : []
      )
    ]) : []
  ])

  # Provider-level defaults application
  provider_with_defaults = local.parsed_config_resolved == null ? null : merge(
    try(local.parsed_config_resolved.provider, {}),
    {
      # Strip any unresolved ${...} markers from the stage before it is baked into
      # resource names: an unresolved variable (e.g. a missing ${env:STAGE} with no
      # default) would otherwise leak into IAM role / function names and fail the
      # provider's name charset check with an opaque error. Falls back to "dev" if
      # stripping leaves it empty. Strict variable validation still surfaces the
      # underlying unresolved reference separately.
      stage      = coalesce(replace(coalesce(var.stage_override, try(local.parsed_config_resolved.provider.stage, null), "dev"), "/\\$\\{[^}]*\\}/", ""), "dev")
      region     = coalesce(try(local.parsed_config_resolved.provider.region, null), var.aws_region, "us-east-1")
      memorySize = coalesce(try(local.parsed_config_resolved.provider.memorySize, null), 1024)
      timeout    = coalesce(try(local.parsed_config_resolved.provider.timeout, null), 6)
      # Runtime has NO default - must be explicitly specified (strict validation)
    }
  )

  # Concrete set(string) of function names.
  # toset([for k, v in map : tostring(k)]) forces Terraform to resolve the iteration
  # keys as set(string) rather than any-typed, preventing for_each unknown-key errors
  # when sam_template_parameters contains computed ARNs from co-planned resources.
  #
  # SAM: derive names from the STRUCTURAL template parse (local.sam_structure), NOT
  # from local.parsed_config.functions and NOT from local.sam_raw. parsed_config and
  # sam_raw both embed resolved sam_template_parameters: when any parameter is a
  # co-planned ARN (unknown at plan, e.g. on a greenfield apply) the resolved
  # data-source read is DEFERRED to apply and everything derived from it is unknown,
  # which propagates into every for_each/count. sam_structure depends only on the
  # template file, so its resource keys are always known at plan.
  _function_names = toset(
    var.config_format == "sam" && local.sam_structure != null ? [
      for logical_id, resource in try(local.sam_structure.Resources, {}) : tostring(logical_id)
      if try(resource.Type, "") == "AWS::Serverless::Function"
      ] : [
      for k, v in try(local.parsed_config.functions, {}) : tostring(k)
    ]
  )

  # Per-function event lists keyed by function name, sourced structurally so each
  # event's TYPE and INDEX (which feed for_each keys downstream) are known at plan even
  # when function values carry unknown resolved parameters. For SAM this is the
  # template-derived event map; otherwise the parsed-config events (known for yaml/ts).
  #
  # JSON-laundered to the dynamic `any` type: the SAM branch (sam_function_events,
  # keyed by SAM logical IDs) and the yaml/ts branch (keyed by function names) are
  # differently-shaped object types that a bare ternary cannot unify ("Inconsistent
  # conditional result types"). Encoding both branches to a string and decoding once
  # yields `any` — the same idiom used for parsed_config and sam_resources_translated.
  # Values here are plan-known (template-/file-derived), so the laundering does not
  # introduce unknowns and the downstream plan-known-key invariants are preserved.
  _function_events = jsondecode(
    var.config_format == "sam" ? jsonencode(local.sam_function_events) : jsonencode({
      for func_name in local._function_names :
      func_name => try(local.functions_with_defaults_prevalidation[func_name].events, [])
    })
  )

  # Structural "does this function declare a VPC config" flag, so the lambda_vpc
  # attachment's for_each keys are plan-known (length(func.vpc_config.subnet_ids) on
  # the resolved function goes unknown when subnet IDs come from co-planned values).
  _function_has_vpc = var.config_format == "sam" && local.sam_structure != null ? {
    for logical_id, resource in try(local.sam_structure.Resources, {}) :
    logical_id => try(resource.Properties.VpcConfig, null) != null
    if try(resource.Type, "") == "AWS::Serverless::Function"
    } : {
    for func_name in local._function_names :
    func_name => try(length(local.functions_with_defaults[func_name].vpc_config.subnet_ids), 0) > 0
  }

  # Structural handler/runtime, sourced straight from the template. The AWS provider
  # requires both to be known at plan for Zip-package functions; reading them from the
  # resolved function object makes them unknown whenever any sam_template_parameter is a
  # co-planned (unknown) value, because the parsed object is dynamically typed and a
  # single unknown leaf renders the whole object unknown. These depend only on
  # sam_structure (the plan-time-known parse).
  _function_handler = var.config_format == "sam" && local.sam_structure != null ? {
    for fn in local._function_names :
    fn => tostring(try(local.sam_structure.Resources[fn].Properties.Handler, "index.handler"))
  } : {}
  _function_runtime = var.config_format == "sam" && local.sam_structure != null ? {
    for fn in local._function_names :
    fn => try(coalesce(
      try(tostring(local.sam_structure.Resources[fn].Properties.Runtime), null),
      try(tostring(local.sam_structure.Globals.Function.Runtime), null),
    ), null)
  } : {}

  # Structural CodeUri per function (drives the S3 artefact key). Sourced from the
  # template so the lambda's s3_key stays known at plan regardless of unknown params.
  _function_code_uri = {
    for fn in local._function_names :
    fn => var.config_format == "sam" && local.sam_structure != null ?
    tostring(try(local.sam_structure.Resources[fn].Properties.CodeUri, "")) :
    tostring(try(local.functions_with_defaults[fn].code_uri, ""))
  }

  # Structural custom resources: logical ID → resource from the plan-time-known
  # source. SAM: the structural parse (parameter-independent). YAML/TS: parsed_config,
  # which is file-derived and known at plan (only resolved_config can go unknown).
  # Drives custom-resource for_each KEYS, Type categorization, and property-presence
  # filters; resource VALUES still come from resolved_config via custom_resources_raw.
  # JSON-laundered to `any`: the two branches are differently-shaped object types
  # that a bare ternary cannot unify ("Inconsistent conditional result types").
  _custom_resources_structure = jsondecode(
    var.config_format == "sam" ? jsonencode(local.sam_custom_resources_structure) : jsonencode(try(local.parsed_config.resources.Resources, {}))
  )

  # Concrete set(string) of CloudFormation custom resource logical IDs — same fix.
  _custom_resource_names = toset([
    for k, v in local._custom_resources_structure : tostring(k)
  ])

  # Plan-time-known CloudFormation Type per custom resource. The category maps below
  # MUST filter on this (never on the resolved resource values): on greenfield the
  # resolved values are unknown, and a for-expression whose `if` condition is unknown
  # makes the whole resulting map unknown → "Invalid for_each argument".
  _custom_resource_types = {
    for k, v in local._custom_resources_structure : tostring(k) => tostring(try(v.Type, ""))
  }

  # Function-level default inheritance (before validation)
  # Used for parsing events - cannot depend on validation_errors
  functions_with_defaults_prevalidation = {
    for func_name in local._function_names :
    func_name => merge(
      try(local.parsed_config.functions[func_name], {}),
      {
        runtime    = try(coalesce(try(local.parsed_config.functions[func_name].runtime, null), try(local.parsed_config.provider.runtime, null)), null)
        memorySize = coalesce(try(local.parsed_config.functions[func_name].memorySize, null), local.provider_with_defaults.memorySize)
        timeout    = coalesce(try(local.parsed_config.functions[func_name].timeout, null), local.provider_with_defaults.timeout)
      }
    )
  }

  # Function-level default inheritance (after validation)
  # Keys are always the static logical IDs from the config schema so that for_each is
  # deterministic even when sam_template_parameters contains unknown values (e.g. ARNs
  # from resources being created in the same plan).  Validation errors are surfaced at
  # apply time via the null_resource.config_validation precondition; all resources that
  # depend on this local must carry depends_on = [null_resource.config_validation].
  # nonsensitive(): function names/structure are never secrets; SAM params (ARNs, config
  # strings) are visible in the AWS console. Stripping here prevents the sensitivity flag
  # from propagating into for_each resource maps and remote-state ARNs tainting keys.
  # Iterate _function_names (concrete set(string)) rather than the any-typed
  # prevalidation map so Terraform can always verify the keys at plan time, even
  # when sam_template_parameters contains unknown ARNs from co-planned resources.
  functions_with_defaults = nonsensitive({
    for func_name in local._function_names :
    func_name => local.functions_with_defaults_prevalidation[func_name]
  })

  # S3 artefact name derivation (used only when var.lambda_code_source.type == "s3").
  # Maps each function logical ID to the artefact name embedded in the S3 key:
  #   "scheduler-service/<artefact_name>/<sha>.zip"
  # Rule: take the function's CodeUri, strip a trailing "dist" or "dist/" segment,
  # and use the last remaining path component. Falls back to the function logical ID
  # in lower-kebab-case if CodeUri is absent. Examples:
  #   "jobs/panel-session-sweeper/dist/" -> "panel-session-sweeper"
  #   "jobs/foo/"                        -> "foo"
  #   "" (no CodeUri)                    -> lowercased function key
  s3_artefact_names = {
    for func_name in local._function_names :
    func_name => (
      # Guard on the FILTERED segment list, not just code_uri != "": a CodeUri of
      # "./" (function code at the template root) trims to an empty segment list,
      # which element() rejects — fall back to the function name in that case.
      length([for seg in split("/", trimsuffix(trimsuffix(trimprefix(local._function_code_uri[func_name], "./"), "/"), "/dist")) : seg if seg != "" && seg != "dist"]) > 0 ?
      element(
        [for seg in split("/", trimsuffix(trimsuffix(trimprefix(local._function_code_uri[func_name], "./"), "/"), "/dist")) : seg if seg != "" && seg != "dist"],
        length([for seg in split("/", trimsuffix(trimsuffix(trimprefix(local._function_code_uri[func_name], "./"), "/"), "/dist")) : seg if seg != "" && seg != "dist"]) - 1
      ) :
      lower(func_name)
    )
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
  # Provider-level iamRoleStatements.
  # SAM: statically [] — sam_as_sls_config.provider never defines iamRoleStatements,
  # and reading through the (possibly unknown-at-plan) parsed_config would make
  # length() checks in key-driving locals (_function_has_policies) unknown.
  # JSON-laundered to `any` — the [] and tuple branches cannot unify in a bare ternary.
  provider_iam_statements = jsondecode(
    var.config_format == "sam" ? "[]" : jsonencode(try(local.parsed_config.provider.iamRoleStatements, []))
  )

  # Normalize provider-level statements (Action/Resource: string -> array)
  provider_iam_statements_normalized = [
    for stmt in local.provider_iam_statements :
    merge(stmt, {
      Action   = try(tolist(stmt.Action), [stmt.Action])
      Resource = try(tolist(stmt.Resource), [stmt.Resource])
    })
  ]

  # Function-level iamRoleStatements (map of function_name -> statements).
  # Iterate _function_names (structural keys) rather than the value-contaminated
  # prevalidation map so the map's keys stay known at plan; statement VALUES may be
  # unknown (resolved ARNs) but that is fine — they are only rendered into the policy
  # document at apply, never used as a for_each key.
  function_iam_statements = {
    for func_name in local._function_names :
    func_name => try(local.functions_with_defaults_prevalidation[func_name].iamRoleStatements, [])
  }

  # Normalize function-level statements (Action/Resource: string -> array)
  function_iam_statements_normalized = {
    for func_name, stmts in local.function_iam_statements :
    func_name => [
      for stmt in stmts :
      merge(stmt, {
        # Final [] fallback: a statement missing Action/Resource entirely must
        # normalise to an empty list (not crash) so the IAM validation rules can
        # report a clean error — tolist(<undefined>) and [<undefined>] both throw.
        Action   = try(tolist(stmt.Action), [stmt.Action], [])
        Resource = try(tolist(stmt.Resource), [stmt.Resource], [])
      })
    ]
  }

  # Merge provider and function statements per function. Keyed by _function_names so
  # keys are plan-known even when statement values carry unknown resolved ARNs.
  merged_iam_statements = nonsensitive({
    for func_name in local._function_names :
    func_name => concat(
      local.provider_iam_statements_normalized,
      try(local.function_iam_statements_normalized[func_name], [])
    )
  })

  # Whether each function needs a custom policy resource. Computed STRUCTURALLY so the
  # functions_with_policies for_each keys are known at plan: a function gets a policy if
  # the provider declares statements, or the template attaches Policies to it. (Using
  # length(statements) on merged_iam_statements would go unknown when statement Resource
  # values are co-planned ARNs.)
  _function_has_policies = var.config_format == "sam" && local.sam_structure != null ? {
    for logical_id, resource in try(local.sam_structure.Resources, {}) :
    logical_id => (
      length(local.provider_iam_statements_normalized) > 0 ||
      length(flatten([
        # Iterate the Policies / Statement lists directly (no tolist). A SAM
        # Policies list is heterogeneous when it mixes policy templates (e.g.
        # `VPCAccessPolicy: {}`) with inline `Statement` documents, and a
        # Statement list is heterogeneous when statements differ in shape (some
        # carry a Condition, mix string/list Resource, or an `!If`-gated entry).
        # tolist() can't unify those element types and throws, which `try` then
        # swallows to `[]` — silently marking the function as having no policy
        # even though its statements parse fine in sam-parser.tf. Direct
        # iteration tolerates the heterogeneity.
        for policy in try(resource.Properties.Policies, []) :
        [for stmt in try(policy.Statement, []) : stmt]
      ])) > 0
    )
    if try(resource.Type, "") == "AWS::Serverless::Function"
    } : {
    for func_name in local._function_names :
    func_name => length(try(local.merged_iam_statements[func_name], [])) > 0
  }

  # Functions requiring custom policies (non-empty statements). Functions that
  # use an explicit Role are excluded — they own their permissions, and the
  # module creates no per-function role to attach a policy to.
  functions_with_policies = nonsensitive({
    for func_name in local._function_names :
    func_name => local.merged_iam_statements[func_name]
    if try(local._function_has_policies[func_name], false) && !try(local._function_has_explicit_role[func_name], false)
  })

  # HTTP Event Parsing (Roadmap #4)
  # Extract all HTTP events from all functions
  # Use prevalidation version to avoid circular dependency
  http_events = nonsensitive(flatten([
    for func_name, events in local._function_events : [
      for event in events :
      merge({
        function_name = func_name
        handler       = tostring(try(local.functions_with_defaults_prevalidation[func_name].handler, ""))
        runtime       = tostring(try(local.functions_with_defaults_prevalidation[func_name].runtime, ""))
        http_method   = ""
        http_path     = ""
        cors_enabled  = false
        cors_config = {
          origin  = null
          headers = null
        }
        # API Gateway v2 (HTTP API) attach-to-existing fields. For native SLS
        # (yaml/ts) configs these stay at their defaults, so http_events behaves
        # exactly as before and every event flows down the v1 REST path.
        #   api_id != null            → attach to a shared apigatewayv2 API (v2 path)
        #   type                      → "Api" (v1 REST) or "HttpApi" (v2)
        #   payload_format_version    → AWS_PROXY payload version for v2 integrations
        #   authorizer                → SAM HttpApi authorizer name, or null
        api_id                 = null
        type                   = ""
        payload_format_version = "2.0"
        authorizer             = null
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

        # v2 fields — only present on SAM HttpApi events (parser emits them);
        # native SLS http events leave these as the defaults above.
        api_id                 = try(event.http.apiId, null)
        type                   = tostring(try(event.http.type, ""))
        payload_format_version = tostring(try(event.http.payloadFormatVersion, "2.0"))
        authorizer             = try(event.http.authorizer, null)
      })
      if can(event.http)
    ]
  ]))

  # HTTP events that drive the self-created v1 REST API (main.tf). An event with
  # a non-null api_id targets an EXISTING shared apigatewayv2 (HTTP API) instead,
  # so it must NOT create any v1 REST resources. For native SLS configs no event
  # ever carries an api_id, so http_v1_events == http_events and the v1 path is
  # unchanged.
  http_v1_events = [
    for event in local.http_events : event if event.api_id == null
  ]

  # HTTP events that attach to an existing apigatewayv2 API (v2 path, http-api-v2.tf).
  # Excludes self-created HttpApi events (ApiId is a !Ref to a template
  # AWS::Serverless::HttpApi resource — handled by http-api-v2-self.tf) so a
  # self-targeted event never reaches the attach path with an unresolved ApiId.
  http_api_v2_events = [
    for event in local.http_events : event
    if event.api_id != null && !contains(local.sam_all_http_api_ids, replace(tostring(event.api_id), local._unresolved_ref_prefix, ""))
  ]

  # Keyed map for the v2 path: "<function>-<METHOD>-<sanitized_path>" → event.
  # Path is sanitized (/{} → _) so the key is a valid for_each key and unique
  # per method+path on a function.
  http_api_v2_event_map = {
    for event in local.http_api_v2_events :
    "${event.function_name}-${upper(event.http_method)}-${replace(replace(replace(trimprefix(event.http_path, "/"), "/", "_"), "{", ""), "}", "")}" => event
  }

  # Resolved HttpApi authorizer defs (http-api-v2.tf for_each source), keyed by
  # authorizer name. Only authorizers actually referenced by a v2 event are kept,
  # and the api_id is taken from the referencing event(s) so the authorizer
  # attaches to the same shared API as its routes.
  # function_name is mapped to a template Function logical ID when the parsed
  # function_ref matches one (so aws_lambda_function.functions[...] resolves);
  # otherwise it stays as the raw ref and validation surfaces the mismatch.
  http_api_v2_authorizers = {
    for auth_name, auth_def in local.sam_http_api_authorizers :
    auth_name => merge(auth_def, {
      api_id = try([
        for event in local.http_api_v2_events :
        event.api_id if event.authorizer == auth_name
      ][0], null)
      # function_ref is the parsed Function logical ID or its resolved
      # FunctionName; map either back to the logical ID so
      # aws_lambda_function.functions[<id>] resolves. If it matches neither,
      # http_api_v2_authorizer_errors surfaces the mismatch.
      function_name = try(local._function_name_to_logical[auth_def.function_ref], auth_def.function_ref)
    })
    # Only emit authorizers a route references, and only when their API is known.
    if length([for event in local.http_api_v2_events : event if event.authorizer == auth_name]) > 0
  }

  # Validation: an HttpApi authorizer must resolve to a template Function logical
  # ID (so aws_lambda_function.functions[...] exists). Reported up-front rather
  # than failing with an opaque for_each/index error in http-api-v2.tf.
  http_api_v2_authorizer_errors = [
    for auth_name, auth in local.http_api_v2_authorizers :
    "HttpApi authorizer '${auth_name}' references function '${auth.function_name}', which is not a Function in the template. Its FunctionArn/FunctionInvokeArn must !Ref/!GetAtt a template AWS::Serverless::Function."
    if !contains(local._function_names, auth.function_name)
  ]

  # Deduplicate functions with HTTP events for permissions (v1 path only — v2
  # emits its own per-route permissions in http-api-v2.tf).
  functions_with_http_events = toset([
    for event in local.http_v1_events : event.function_name
  ])

  # HTTP event validation errors
  http_event_validation_errors = flatten([
    for event in local.http_events : concat(
      # Validate HTTP method
      !contains(["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "ANY"], event.http_method) ?
      ["Function '${event.function_name}' has invalid HTTP method '${event.http_method}'. Must be one of: GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS, ANY."] : [],

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
  # Extract unique paths from HTTP events. v1 ONLY — v2 (api_id != null) events
  # do not build a REST resource tree; they emit apigatewayv2 routes directly.
  all_paths = toset([
    for event in local.http_v1_events : event.http_path
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
        for event in local.http_v1_events :
        event.http_path == path && event.cors_enabled
      ])
      # Collect all methods on this path
      methods = distinct([
        for event in local.http_v1_events :
        event.http_method if event.http_path == path
      ])
      # Merge custom CORS configs (take first non-null custom config if any)
      custom_config = try(
        [
          for event in local.http_v1_events :
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
    for func_name, events in local._function_events : [
      for idx, event in events :
      try(event.s3, null) != null ? {
        function_name = func_name
        event_index   = idx
        s3_config     = event.s3
      } : null
    ]
  ])

  # Normalize both shorthand and object syntax to consistent format
  s3_events_normalized = nonsensitive([
    for evt in nonsensitive(local.s3_events_raw) :
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
  ])

  # Parse custom bucket properties from provider.s3 section
  s3_buckets_custom_properties = try(local.parsed_config.provider.s3, {})

  # Identify unique buckets that need to be created (not existing)
  s3_buckets_to_create = nonsensitive({
    for bucket_key in distinct([
      for evt in nonsensitive(local.s3_events_normalized) :
      evt.bucket_key if !evt.existing
    ]) :
    bucket_key => {
      name       = try(local.s3_buckets_custom_properties[bucket_key].name, bucket_key)
      properties = try(local.s3_buckets_custom_properties[bucket_key], {})
    }
  })

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

      # Validate S3 bucket naming conventions (skipped for SAM: bucket refs are CloudFormation logical IDs)
      var.config_format != "sam" && !can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", evt.bucket_name)) ?
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
  event_source_mappings = nonsensitive(merge([
    for func_name, events in local._function_events : {
      for idx, event in events :
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
  ]...))

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

      # Validate DynamoDB stream ARN format (skipped for SAM: !GetAtt refs aren't real ARNs at plan time)
      mapping.type == "stream" && var.config_format != "sam" && !can(regex("^arn:aws:dynamodb:[^:]+:[^:]+:table/[^/]+/stream/.+$", mapping.arn)) ?
      ["Function '${mapping.function_name}' event[${mapping.event_index}]: Invalid DynamoDB stream ARN format. Expected pattern: arn:aws:dynamodb:region:account:table/TableName/stream/StreamLabel"] : [],

      # Validate SQS queue ARN format (skipped for SAM: !Ref refs aren't real ARNs at plan time)
      mapping.type == "sqs" && var.config_format != "sam" && !can(regex("^arn:aws:sqs:[^:]+:[^:]+:.+$", mapping.arn)) ?
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
    for func_name, events in local._function_events : [
      for event_idx, event in events : {
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
  # tostring() forces the key to string type so Terraform sees a concrete key
  # even when event is any-typed (from iterating any-typed function values).
  schedule_event_map = nonsensitive({
    for event in nonsensitive(local.all_schedule_events) :
    tostring(event.event_key) => event
  })

  # Flatten eventBridge events from all functions
  # EventBridge events support event patterns and custom event buses
  all_eventbridge_events = flatten([
    for func_name, events in local._function_events : [
      for event_idx, event in events : {
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
  # tostring() forces the key to string type (same rationale as schedule_event_map).
  eventbridge_event_map = nonsensitive({
    for event in nonsensitive(local.all_eventbridge_events) :
    tostring(event.event_key) => event
  })

  # ============================================================================
  # Custom Resource Parsing (Roadmap #9)
  # ============================================================================

  # Extract resources section from serverless config (with variable resolution)
  custom_resources_raw = {
    for logical_id in local._custom_resource_names :
    logical_id => try(local.resolved_config.resources.Resources[logical_id], {})
  }

  # Helper function to convert PascalCase to snake_case
  # Example: MyBucket -> my_bucket, UsersTable -> users_table
  # Terraform replace() doesn't support capture groups well, so we use a simple approach
  to_snake_case = {
    for logical_id, resource in local.custom_resources_raw :
    logical_id => lower(join("_", regexall("[A-Z][a-z0-9]*", logical_id)))
  }

  # Categorize resources by type, filtered by var.resource_types allowlist.
  # null means all types are created (default / backward-compatible behaviour).
  # A list restricts creation to only the named CloudFormation types.
  # Lambda functions, IAM roles, and all event wiring are always created
  # regardless of this filter — it only gates standalone infrastructure resources.

  s3_buckets = {
    for logical_id, resource in local.custom_resources_raw :
    logical_id => resource
    if local._custom_resource_types[logical_id] == "AWS::S3::Bucket"
    && (var.resource_types == null || contains(var.resource_types, "AWS::S3::Bucket"))
  }

  dynamodb_tables = {
    for logical_id, resource in local.custom_resources_raw :
    logical_id => resource
    if local._custom_resource_types[logical_id] == "AWS::DynamoDB::Table"
    && (var.resource_types == null || contains(var.resource_types, "AWS::DynamoDB::Table"))
  }

  sns_topics = {
    for logical_id, resource in local.custom_resources_raw :
    logical_id => resource
    if local._custom_resource_types[logical_id] == "AWS::SNS::Topic"
    && (var.resource_types == null || contains(var.resource_types, "AWS::SNS::Topic"))
  }

  sqs_queues = {
    for logical_id, resource in local.custom_resources_raw :
    logical_id => resource
    if local._custom_resource_types[logical_id] == "AWS::SQS::Queue"
    && (var.resource_types == null || contains(var.resource_types, "AWS::SQS::Queue"))
  }

  cloudfront_distributions = {
    for logical_id, resource in local.custom_resources_raw :
    logical_id => resource
    if local._custom_resource_types[logical_id] == "AWS::CloudFront::Distribution"
    && (var.resource_types == null || contains(var.resource_types, "AWS::CloudFront::Distribution"))
  }

  log_groups = {
    for logical_id, resource in local.custom_resources_raw :
    logical_id => resource
    if local._custom_resource_types[logical_id] == "AWS::Logs::LogGroup"
    && (var.resource_types == null || contains(var.resource_types, "AWS::Logs::LogGroup"))
  }

  # Supported resource types
  supported_resource_types = toset([
    "AWS::S3::Bucket",
    "AWS::DynamoDB::Table",
    "AWS::SNS::Topic",
    "AWS::SQS::Queue",
    "AWS::CloudFront::Distribution",
    "AWS::Logs::LogGroup",
    # IAM roles (iam-roles.tf)
    "AWS::IAM::Role",
    # WebSocket API (websocket-api.tf): the Api drives creation; Route/Integration/
    # Stage are consumed by it; Deployment is subsumed by stage auto_deploy.
    "AWS::ApiGatewayV2::Api",
    "AWS::ApiGatewayV2::Route",
    "AWS::ApiGatewayV2::Integration",
    "AWS::ApiGatewayV2::Stage",
    "AWS::ApiGatewayV2::Deployment",
    # Step Functions (step-functions.tf)
    "AWS::Serverless::StateMachine",
    "AWS::StepFunctions::StateMachine",
    # Explicit Lambda invoke permissions are subsumed by the module's own
    # auto-generated aws_lambda_permission resources for its APIs.
    "AWS::Lambda::Permission",
    # Standalone event source mappings (event-source-mappings-cfn.tf)
    "AWS::Lambda::EventSourceMapping"
  ])

  # Identify unsupported resource types for validation.
  # Only reports types that would actually be created (i.e. not excluded by resource_types),
  # so a resource_types allowlist silences errors for intentionally-skipped types.
  unsupported_resources = {
    for logical_id, type in local._custom_resource_types :
    logical_id => type
    if type != ""
    && !contains(local.supported_resource_types, type)
    && (var.resource_types == null || contains(var.resource_types, type))
  }

  # Validation errors for unsupported resources
  custom_resource_validation_errors = [
    for logical_id, type in local.unsupported_resources :
    "Unsupported CloudFormation resource type '${type}' for resource '${logical_id}'. Supported types: S3::Bucket, DynamoDB::Table, SNS::Topic, SQS::Queue, CloudFront::Distribution, Logs::LogGroup."
  ]

  # ============================================================================
  # CloudFront Event Parsing (Roadmap #12)
  # ============================================================================

  # Extract cloudFront events from function definitions (Lambda@Edge)
  # Supports both string and object origin syntax:
  #   origin: "https://example.com"
  #   origin: { DomainName: "example.com", CustomOriginConfig: { ... } }
  cloudfront_events_raw = nonsensitive(flatten([
    for func_name, events in local._function_events : [
      for event_idx, event in events : {
        function_name   = func_name
        event_index     = event_idx
        event_key       = "${func_name}-cloudfront-${event_idx}"
        event_type      = try(event.cloudFront.eventType, "")
        origin          = try(event.cloudFront.origin, null)
        behavior        = try(event.cloudFront.behavior, {})
        path_pattern    = try(event.cloudFront.pathPattern, null)
        include_body    = try(event.cloudFront.includeBody, false)
        distribution    = try(event.cloudFront.distribution, "default")
        cache_policy_id = try(event.cloudFront.cachePolicy.id, null)
      } if can(event.cloudFront)
    ]
  ]))

  # Functions that have cloudFront events - require publish=true and edge trust policy
  functions_with_cloudfront_events = toset([
    for event in local.cloudfront_events_raw : event.function_name
  ])

  # Group events by distribution key to create one distribution per group.
  # Events without an explicit distribution reference use the "default" key.
  cloudfront_distribution_groups = {
    for dist_key in distinct([for ev in local.cloudfront_events_raw : ev.distribution]) :
    dist_key => [for ev in local.cloudfront_events_raw : ev if ev.distribution == dist_key]
  }

  # Prepared distribution configs for resource creation.
  # Excludes groups referencing existing AWS::CloudFront::Distribution resources.
  cloudfront_lambda_edge_distributions = nonsensitive({
    for dist_key, events in nonsensitive(local.cloudfront_distribution_groups) :
    dist_key => {
      events = events
      primary_origin = {
        domain_name = try(
          events[0].origin.DomainName,
          replace(replace(replace(tostring(events[0].origin), "https://", ""), "http://", ""), "s3://", "")
        )
        origin_id = try(events[0].origin.Id, events[0].function_name)
        is_s3     = try(events[0].origin.S3OriginConfig, null) != null || can(regex("^s3://", tostring(events[0].origin)))
        protocol = try(
          events[0].origin.CustomOriginConfig.OriginProtocolPolicy,
          can(regex("^http://", tostring(events[0].origin))) ? "http-only" : "https-only"
        )
        oai = try(events[0].origin.S3OriginConfig.OriginAccessIdentity, "")
      }
      default_events = [for ev in events : ev if ev.path_pattern == null]
      ordered_behaviors = {
        for path in distinct([for ev in events : ev.path_pattern if ev.path_pattern != null]) :
        path => [for ev in events : ev if ev.path_pattern == path]
      }
    }
    if !contains(keys(local.cloudfront_distributions), dist_key)
  })

  # CloudFront event validation errors
  cloudfront_event_validation_errors = flatten([
    for event in local.cloudfront_events_raw : concat(
      !contains(["viewer-request", "viewer-response", "origin-request", "origin-response"], event.event_type) ?
      ["Function '${event.function_name}' cloudFront event[${event.event_index}]: eventType must be one of: viewer-request, viewer-response, origin-request, origin-response. Got: '${event.event_type}'."] : [],

      event.origin == null ?
      ["Function '${event.function_name}' cloudFront event[${event.event_index}]: 'origin' is required."] : [],

      contains(["viewer-response", "origin-response"], event.event_type) && event.include_body ?
      ["Function '${event.function_name}' cloudFront event[${event.event_index}]: includeBody can only be true for viewer-request or origin-request events."] : [],

      contains(["viewer-request", "viewer-response"], event.event_type) &&
      try(local.functions_with_defaults_prevalidation[event.function_name].timeout, 6) > 5 ?
      ["Function '${event.function_name}' cloudFront event[${event.event_index}]: viewer-side Lambda@Edge functions must have timeout <= 5 seconds. Current: ${try(local.functions_with_defaults_prevalidation[event.function_name].timeout, 6)}s."] : [],

      contains(["origin-request", "origin-response"], event.event_type) &&
      try(local.functions_with_defaults_prevalidation[event.function_name].timeout, 6) > 30 ?
      ["Function '${event.function_name}' cloudFront event[${event.event_index}]: origin-side Lambda@Edge functions must have timeout <= 30 seconds. Current: ${try(local.functions_with_defaults_prevalidation[event.function_name].timeout, 6)}s."] : [],

      contains(["viewer-request", "viewer-response"], event.event_type) &&
      try(local.functions_with_defaults_prevalidation[event.function_name].memorySize, local.provider_with_defaults.memorySize) > 128 ?
      ["Function '${event.function_name}' cloudFront event[${event.event_index}]: viewer-side Lambda@Edge functions must have memorySize <= 128 MB. Current: ${try(local.functions_with_defaults_prevalidation[event.function_name].memorySize, local.provider_with_defaults.memorySize)}MB. Set memorySize: 128 in the function definition."] : []
    )
  ])
}
