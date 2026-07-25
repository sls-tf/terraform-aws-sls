# ============================================================================
# Lambda naming-convention lint
# ============================================================================
# When a function omits an explicit name, the module generates
# "${service}-${stage}-${key}". For a brownfield migration that generated name
# must match what is ALREADY deployed — a mismatch doesn't surface as a plan
# diff but as a full function replace (the physical name changed). Nothing in
# the SAM spec hints an explicit FunctionName is needed, so this is easy to
# miss on exactly the resource type that "maps cleanly".
#
# The check below emits a plan-time WARNING (not an error) when a
# resource_types allowlist is in use — the signal that this template scopes an
# existing deployment rather than greenfield — and any function relies on a
# generated name. The generated names are also exported via the
# functions_with_generated_names output so they can be diffed against
# `aws lambda list-functions` before the first plan.

locals {
  # Shared "<service>-<stage>" (or "<stage>-<service>") prefix for every
  # generated resource name — functions, execution roles/policies, alarm-set
  # lambda names. var.generated_name_order flips the segment order for parity
  # with platform modules that put the environment first.
  # try() on stage: on invalid-config paths provider_with_defaults is null and
  # this local must stay evaluable so config_validation reports the REAL error.
  _generated_name_prefix = var.generated_name_order == "stage-service" ? (
    "${try(local.provider_with_defaults.stage, "dev")}-${try(local.parsed_config_resolved.service, "unknown")}"
    ) : (
    "${try(local.parsed_config_resolved.service, "unknown")}-${try(local.provider_with_defaults.stage, "dev")}"
  )

  # Presence from the STRUCTURAL parse so the check condition stays plan-known
  # even when resolved values (e.g. a FunctionName built from an unknown
  # parameter) are not.
  _function_has_explicit_name = {
    for fn in local._function_names :
    fn => var.config_format == "sam" ? (
      local.sam_structure != null && try(local.sam_structure.Resources[fn].Properties.FunctionName, null) != null
      ) : (
      try(local.parsed_config.functions[fn].name, null) != null
    )
  }

  functions_with_generated_names = {
    for fn in local._function_names :
    fn => "${local._generated_name_prefix}-${fn}"
    if !local._function_has_explicit_name[fn]
  }
}

check "lambda_naming_convention" {
  assert {
    # Keyed off the structural presence map (not the generated-name values,
    # which may be unknown on greenfield) so this evaluates at plan.
    condition = !(var.naming_convention_warning && var.resource_types != null && length([for fn, has in local._function_has_explicit_name : fn if !has]) > 0)
    # Function KEYS only — generated name VALUES can be unknown on greenfield,
    # and an unknown error_message invalidates the whole check.
    error_message = join(" ", [
      "resource_types is scoped (brownfield posture) but these functions have no explicit name and will use module-generated \"<service>-<stage>-<key>\" names:",
      join(", ", [for fn, has in local._function_has_explicit_name : fn if !has]),
      "— see the functions_with_generated_names output and verify each matches the already-deployed function name (aws lambda list-functions), otherwise the plan will REPLACE the function. Set an explicit name/FunctionName to pin it."
    ])
  }
}
