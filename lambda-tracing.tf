# ============================================================================
# Lambda X-Ray tracing
# ============================================================================
# SAM: `Tracing: Active` per function or in Globals.Function (folded into the
# function's `tracing` by the parser). Serverless yaml: `tracing: true|Active`
# per function, or `provider.tracing.lambda: true` for every function.
# Functions with tracing get tracing_config { mode = "Active" } (see main.tf)
# and — when they use the module-created role — the AWSXRayDaemonWriteAccess
# managed policy. Without this the swap ships a silent observability
# regression: no plan diff, tracing just stops.

locals {
  _tracing_mode_values = {
    "true"        = "Active"
    "active"      = "Active"
    "passthrough" = "PassThrough"
  }

  # Resolved tracing mode per function ("Active" / "PassThrough" / null).
  # Function-level value wins; yaml provider.tracing.lambda is the fleet-wide
  # default; false/absent -> null (Lambda default). Read from STRUCTURAL
  # sources (sam_structure / raw parsed_config) so the xray-attachment
  # for_each keys stay plan-known on greenfield.
  _function_tracing_mode = {
    for fn in local._function_names :
    fn => try(
      local._tracing_mode_values[lower(tostring(coalesce(
        var.config_format == "sam" ? (
          try(local.sam_structure.Resources[fn].Properties.Tracing, try(local.sam_structure.Globals.Function.Tracing, null))
        ) : try(local.parsed_config.functions[fn].tracing, null),
        # yaml-only fleet default — for SAM this would read the RESOLVED parse
        # (possibly unknown), and SAM's fleet default is Globals above anyway.
        var.config_format == "sam" ? null : try(local.parsed_config.provider.tracing.lambda, null)
      )))],
      null
    )
  }
}

# X-Ray write permission for actively-traced functions on module-created roles.
resource "aws_iam_role_policy_attachment" "lambda_xray" {
  for_each = {
    for fn in local._function_names :
    fn => fn
    if local._function_tracing_mode[fn] == "Active" && !try(local._function_has_explicit_role[fn], false)
  }

  role       = aws_iam_role.lambda_execution[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}
