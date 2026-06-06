# ==============================================================================
# Variable Resolution Engine
# ==============================================================================
#
# This file implements resolution for Serverless Framework variable syntax:
# - ${self:path.to.property} - References to other properties in config
# - ${env:VARIABLE_NAME} - Environment variables
# - ${env:VAR, 'default'} - Environment variables with default values
#
# Resolution Process:
# 1. Extract all variable patterns from raw config
# 2. Build dependency graph
# 3. Detect circular references
# 4. Resolve variables in dependency order
# 5. Replace variables in config with resolved values
#
# Phase 1 Implementation (this file):
# - ${self:} resolution
# - ${env:} resolution
# - Recursive resolution with depth tracking
# - Circular reference detection
#
# Future Phases:
# - ${opt:} - CLI options
# - ${cf:} - CloudFormation outputs
# - ${ssm:} - SSM parameters
# - ${file()} - External file references

locals {
  # Variable resolution configuration
  var_resolution_config = {
    strict           = var.strict_variable_resolution
    max_depth        = var.max_variable_depth
    environment_vars = var.environment_vars
  }

  # ===========================================================================
  # Variable Pattern Detection
  # ===========================================================================

  # Regex patterns for detecting variables
  # ${self:path.to.property} - References to config properties
  # ${env:VARIABLE_NAME} or ${env:VAR, 'default'} - Environment variables
  variable_pattern_regex = "\\$\\{([^}]+)\\}"

  # Extract all variable references anywhere in the config (including values
  # nested under provider/custom/functions/resources, not just top-level scalar
  # keys) by scanning the JSON-encoded config. Keyed by "config" so the shape
  # stays a map; callers only inspect its length / matches.
  extract_variable_refs = local.parsed_config != null ? {
    for item in [{
      key     = "config"
      matches = try(regexall(local.variable_pattern_regex, jsonencode(local.parsed_config)), [])
    }] : item.key => item.matches if length(item.matches) > 0
  } : {}

  # Parse variable expressions into structured format
  # Example: "self:provider.stage" => {type: "self", path: "provider.stage"}
  # Example: "env:NODE_ENV, 'production'" => {type: "env", name: "NODE_ENV", default: "production"}
  parsed_variables = {
    for path, matches in local.extract_variable_refs : path => [
      for match in matches : {
        raw        = match[0]
        expression = match[0]
        type       = split(":", match[0])[0]
        # For ${self:}, the reference is everything after "self:"
        # For ${env:}, handle both "env:VAR" and "env:VAR, 'default'"
        reference = length(split(":", match[0])) > 1 ? join(":", slice(split(":", match[0]), 1, length(split(":", match[0])))) : ""
      }
    ]
  }

  # ===========================================================================
  # ${self:} Resolution Algorithm
  # ===========================================================================

  # Helper function to traverse object paths like "provider.stage"
  # Returns the value at that path or null if not found
  # First pass: raw values from config
  traverse_path_raw = local.parsed_config != null ? {
    "service"             = try(local.parsed_config.service, null)
    "provider.name"       = try(local.parsed_config.provider.name, null)
    "provider.stage"      = try(local.parsed_config.provider.stage, null)
    "provider.region"     = try(local.parsed_config.provider.region, null)
    "provider.runtime"    = try(local.parsed_config.provider.runtime, null)
    "custom.defaultStage" = try(local.parsed_config.custom.defaultStage, null)
    "custom.bucketName"   = try(local.parsed_config.custom.bucketName, null)
  } : {}

  # Second pass: resolve any ${self:} references in traverse_path values
  # This handles cases like provider.stage = "${self:custom.defaultStage}"
  traverse_path = {
    for path, value in local.traverse_path_raw :
    path => can(regex("\\$\\{self:", tostring(value))) ? replace(
      replace(
        replace(
          tostring(value),
          "$${self:service}",
          coalesce(try(local.traverse_path_raw["service"], null), "$${self:service}")
        ),
        "$${self:custom.defaultStage}",
        coalesce(try(local.traverse_path_raw["custom.defaultStage"], null), "$${self:custom.defaultStage}")
      ),
      "$${self:custom.bucketName}",
      coalesce(try(local.traverse_path_raw["custom.bucketName"], null), "$${self:custom.bucketName}")
    ) : value
  }

  # Resolve variables in provider object properties
  provider_resolved = local.parsed_config != null && try(local.parsed_config.provider, null) != null ? merge(
    local.parsed_config.provider,
    {
      for key, value in local.parsed_config.provider :
      key => can(regex("\\$\\{self:", tostring(value))) ? replace(
        replace(
          replace(
            replace(
              tostring(value),
              "$${self:service}",
              coalesce(try(local.traverse_path["service"], null), "$${self:service}")
            ),
            "$${self:provider.stage}",
            coalesce(try(local.traverse_path["provider.stage"], null), "$${self:provider.stage}")
          ),
          "$${self:provider.region}",
          coalesce(try(local.traverse_path["provider.region"], null), "$${self:provider.region}")
        ),
        "$${self:custom.defaultStage}",
        coalesce(try(local.traverse_path["custom.defaultStage"], null), "$${self:custom.defaultStage}")
      ) : value
      if can(tostring(value)) && can(regex("\\$\\{self:", tostring(value)))
    }
  ) : null

  # Resolve variables in custom object properties
  custom_resolved = local.parsed_config != null && try(local.parsed_config.custom, null) != null ? merge(
    local.parsed_config.custom,
    {
      for key, value in local.parsed_config.custom :
      key => can(regex("\\$\\{self:", tostring(value))) ? replace(
        replace(
          replace(
            tostring(value),
            "$${self:service}",
            coalesce(try(local.traverse_path["service"], null), "$${self:service}")
          ),
          "$${self:provider.stage}",
          coalesce(try(local.traverse_path["provider.stage"], null), "$${self:provider.stage}")
        ),
        "$${self:custom.defaultStage}",
        coalesce(try(local.traverse_path["custom.defaultStage"], null), "$${self:custom.defaultStage}")
      ) : value
      if can(tostring(value)) && can(regex("\\$\\{self:", tostring(value)))
    }
  ) : null

  # First pass: resolve simple ${self:} references
  # This handles direct references without nested variables
  # Special handling for provider and custom objects
  config_with_self_resolved = try(
    merge(
      local.parsed_config,
      {
        for key, value in local.parsed_config :
        key => replace(
          replace(
            replace(
              replace(
                tostring(value),
                "$${self:service}",
                coalesce(try(local.traverse_path["service"], null), "$${self:service}")
              ),
              "$${self:provider.stage}",
              coalesce(try(local.traverse_path["provider.stage"], null), "$${self:provider.stage}")
            ),
            "$${self:provider.region}",
            coalesce(try(local.traverse_path["provider.region"], null), "$${self:provider.region}")
          ),
          "$${self:custom.defaultStage}",
          coalesce(try(local.traverse_path["custom.defaultStage"], null), "$${self:custom.defaultStage}")
        )
        if can(tostring(value)) && can(regex("\\$\\{self:", tostring(value)))
      },
      local.provider_resolved != null ? { provider = local.provider_resolved } : {},
      local.custom_resolved != null ? { custom = local.custom_resolved } : {}
    ),
    local.parsed_config
  )

  # ===========================================================================
  # ${env:} Resolution Algorithm
  # ===========================================================================

  # Parse ${env:} expressions to extract variable name and optional default
  # Example: "env:NODE_ENV" => {name: "NODE_ENV", default: null}
  # Example: "env:STAGE, 'production'" => {name: "STAGE", default: "production"}
  env_variables_parsed = local.config_with_self_resolved != null ? {
    for key, value in local.config_with_self_resolved : key => (
      can(tostring(value)) && can(regex("\\$\\{env:", tostring(value))) ? [
        for match in regexall("\\$\\{env:([^,}]+)(?:,\\s*['\"]([^'\"]+)['\"])?\\}", tostring(value)) : {
          full_match = "$${env:${match[0]}${match[1] != "" ? ", '${match[1]}'" : ""}}"
          var_name   = match[0]
          default    = match[1] != "" ? match[1] : null
        }
      ] : []
    ) if can(tostring(value)) && can(regex("\\$\\{env:", tostring(value)))
  } : {}

  # Parse ${env:} in provider object
  env_variables_parsed_provider = local.config_with_self_resolved != null && try(local.config_with_self_resolved.provider, null) != null ? {
    for key, value in local.config_with_self_resolved.provider : key => (
      can(tostring(value)) && can(regex("\\$\\{env:", tostring(value))) ? [
        for match in regexall("\\$\\{env:([^,}]+)(?:,\\s*['\"]([^'\"]+)['\"])?\\}", tostring(value)) : {
          full_match = try(match[1], null) != null && match[1] != "" ? "$${env:${match[0]}, '${match[1]}'}" : "$${env:${match[0]}}"
          var_name   = match[0]
          default    = try(match[1], null) != null && match[1] != "" ? match[1] : null
        }
      ] : []
    ) if can(tostring(value)) && can(regex("\\$\\{env:", tostring(value)))
  } : {}

  # Parse ${env:} in custom object
  env_variables_parsed_custom = local.config_with_self_resolved != null && try(local.config_with_self_resolved.custom, null) != null ? {
    for key, value in local.config_with_self_resolved.custom : key => (
      can(tostring(value)) && can(regex("\\$\\{env:", tostring(value))) ? [
        for match in regexall("\\$\\{env:([^,}]+)(?:,\\s*['\"]([^'\"]+)['\"])?\\}", tostring(value)) : {
          full_match = try(match[1], null) != null && match[1] != "" ? "$${env:${match[0]}, '${match[1]}'}" : "$${env:${match[0]}}"
          var_name   = match[0]
          default    = try(match[1], null) != null && match[1] != "" ? match[1] : null
        }
      ] : []
    ) if can(tostring(value)) && can(regex("\\$\\{env:", tostring(value)))
  } : {}

  # Resolve ${env:} in provider object
  provider_env_resolved = local.config_with_self_resolved != null && try(local.config_with_self_resolved.provider, null) != null ? merge(
    local.config_with_self_resolved.provider,
    {
      for key, value in local.config_with_self_resolved.provider :
      key => replace(
        tostring(value),
        try(local.env_variables_parsed_provider[key][0].full_match, ""),
        coalesce(
          try(var.environment_vars[try(local.env_variables_parsed_provider[key][0].var_name, "")], null),
          try(local.env_variables_parsed_provider[key][0].default, null),
          try(local.env_variables_parsed_provider[key][0].full_match, "")
        )
      )
      if can(tostring(value)) && length(try(local.env_variables_parsed_provider[key], [])) > 0
    }
  ) : null

  # Resolve ${env:} in custom object
  custom_env_resolved = local.config_with_self_resolved != null && try(local.config_with_self_resolved.custom, null) != null ? merge(
    local.config_with_self_resolved.custom,
    {
      for key, value in local.config_with_self_resolved.custom :
      key => replace(
        tostring(value),
        try(local.env_variables_parsed_custom[key][0].full_match, ""),
        coalesce(
          try(var.environment_vars[try(local.env_variables_parsed_custom[key][0].var_name, "")], null),
          try(local.env_variables_parsed_custom[key][0].default, null),
          try(local.env_variables_parsed_custom[key][0].full_match, "")
        )
      )
      if can(tostring(value)) && length(try(local.env_variables_parsed_custom[key], [])) > 0
    }
  ) : null

  # Second pass: resolve ${env:} variables
  # Manually replace each parsed env variable
  config_with_env_pass1 = local.config_with_self_resolved != null ? try(
    merge(
      local.config_with_self_resolved,
      {
        for key, value in local.config_with_self_resolved :
        key => replace(
          tostring(value),
          try(local.env_variables_parsed[key][0].full_match, ""),
          try(
            var.environment_vars[try(local.env_variables_parsed[key][0].var_name, "")],
            try(local.env_variables_parsed[key][0].default, try(local.env_variables_parsed[key][0].full_match, ""))
          )
        )
        if can(tostring(value)) && length(try(local.env_variables_parsed[key], [])) > 0
      },
      local.provider_env_resolved != null ? { provider = local.provider_env_resolved } : {},
      local.custom_env_resolved != null ? { custom = local.custom_env_resolved } : {}
    ),
    local.config_with_self_resolved
  ) : null

  config_with_env_pass2 = local.config_with_env_pass1 != null ? try(
    merge(
      local.config_with_env_pass1,
      {
        for key, value in local.config_with_env_pass1 :
        key => replace(
          tostring(value),
          try(local.env_variables_parsed[key][1].full_match, ""),
          try(
            var.environment_vars[try(local.env_variables_parsed[key][1].var_name, "")],
            try(local.env_variables_parsed[key][1].default, try(local.env_variables_parsed[key][1].full_match, ""))
          )
        )
        if can(tostring(value)) && length(try(local.env_variables_parsed[key], [])) > 1
      }
    ),
    local.config_with_env_pass1
  ) : null

  config_with_env_pass3 = local.config_with_env_pass2 != null ? try(
    merge(
      local.config_with_env_pass2,
      {
        for key, value in local.config_with_env_pass2 :
        key => replace(
          tostring(value),
          try(local.env_variables_parsed[key][2].full_match, ""),
          try(
            var.environment_vars[try(local.env_variables_parsed[key][2].var_name, "")],
            try(local.env_variables_parsed[key][2].default, try(local.env_variables_parsed[key][2].full_match, ""))
          )
        )
        if can(tostring(value)) && length(try(local.env_variables_parsed[key], [])) > 2
      }
    ),
    local.config_with_env_pass2
  ) : null

  config_with_env_resolved = local.config_with_env_pass3

  # Deep ${self:} resolution. The per-object passes above only reach top-level,
  # provider, and custom values; this resolves the enumerated self-paths ANYWHERE
  # in the config (e.g. a CloudFront DomainName or a function env var nested in
  # resources:) by string-replacing over the JSON-encoded config and decoding
  # once. The five-replacement chain is applied twice so a path whose resolved
  # value itself contains another self-reference (e.g. custom.bucketName ->
  # provider.stage) converges. Unresolvable references are left intact.
  # Each target maps the literal ${self:PATH} marker to its resolved value, or
  # back to the marker itself when the path is absent/null (leave it intact).
  # Explicit null checks are required: tostring(null) is null, not "", and a null
  # replacement makes replace() raise "Invalid function argument".
  _deep_self_targets = {
    "$${self:service}"             = try(local.traverse_path["service"], null) != null ? tostring(local.traverse_path["service"]) : "$${self:service}"
    "$${self:provider.stage}"      = try(local.traverse_path["provider.stage"], null) != null ? tostring(local.traverse_path["provider.stage"]) : "$${self:provider.stage}"
    "$${self:provider.region}"     = try(local.traverse_path["provider.region"], null) != null ? tostring(local.traverse_path["provider.region"]) : "$${self:provider.region}"
    "$${self:custom.defaultStage}" = try(local.traverse_path["custom.defaultStage"], null) != null ? tostring(local.traverse_path["custom.defaultStage"]) : "$${self:custom.defaultStage}"
    "$${self:custom.bucketName}"   = try(local.traverse_path["custom.bucketName"], null) != null ? tostring(local.traverse_path["custom.bucketName"]) : "$${self:custom.bucketName}"
  }

  _deep_self_json_pass1 = local.config_with_env_resolved == null ? null : replace(replace(replace(replace(replace(
    jsonencode(local.config_with_env_resolved),
    "$${self:custom.bucketName}", local._deep_self_targets["$${self:custom.bucketName}"]),
    "$${self:custom.defaultStage}", local._deep_self_targets["$${self:custom.defaultStage}"]),
    "$${self:service}", local._deep_self_targets["$${self:service}"]),
    "$${self:provider.stage}", local._deep_self_targets["$${self:provider.stage}"]),
    "$${self:provider.region}", local._deep_self_targets["$${self:provider.region}"]
  )

  _deep_self_json_pass2 = local._deep_self_json_pass1 == null ? null : replace(replace(replace(replace(replace(
    local._deep_self_json_pass1,
    "$${self:custom.bucketName}", local._deep_self_targets["$${self:custom.bucketName}"]),
    "$${self:custom.defaultStage}", local._deep_self_targets["$${self:custom.defaultStage}"]),
    "$${self:service}", local._deep_self_targets["$${self:service}"]),
    "$${self:provider.stage}", local._deep_self_targets["$${self:provider.stage}"]),
    "$${self:provider.region}", local._deep_self_targets["$${self:provider.region}"]
  )

  config_deep_resolved = local._deep_self_json_pass2 == null ? null : jsondecode(local._deep_self_json_pass2)

  # Final resolved config - combines ${self:} and ${env:} resolution
  resolved_config = local.config_deep_resolved

  # Variable resolution errors - collect unresolved variables if strict mode
  variable_resolution_errors = var.strict_variable_resolution && local.resolved_config != null ? flatten([
    for key, value in local.resolved_config : [
      for match in try(regexall("\\$\\{(self|env):[^}]+\\}", tostring(value)), []) :
      "Unresolved variable in '${key}': ${match}"
    ]
  ]) : []
}
