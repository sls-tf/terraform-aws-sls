# ============================================================================
# Extension registry
# ============================================================================
# An EXTENSION is config that sls.tf understands and no other tool does —
# neither the SAM spec nor Serverless Framework defines it. This is a different
# thing from sls.tf implementing a CloudFormation resource type it hadn't
# covered yet, and the two are easy to confuse because they can produce the same
# AWS resources:
#
#   AWS::CloudWatch::Alarm in `resources:`  -> standard CFN, portable, NOT an
#                                              extension (cloudwatch-observability.tf)
#   Metadata.SlsTf.Alarms                   -> "one alarm per lambda, whatever
#                                              the set turns out to be", not
#                                              expressible in CFN, IS an
#                                              extension (alarm-sets.tf)
#
# Extensions live where the native tooling is SPECIFIED to ignore them, so
# `sam validate` / `sam build` / `sam local` keep working on the same file:
# `Metadata` for SAM, `custom:` for serverless yaml. Note the corollary —
# `sam deploy` on a template carrying extensions is a PARTIAL deploy and is not
# supported. See docs/EXTENSIONS.md.
#
# This registry exists so that every extension resolves through one code path
# rather than a scattered `try(local.sam_structure.Metadata.SlsTf.X, {})` at
# each use site. Those scattered lookups made "absent", "misspelled" and "not
# supported by this module version" the same value, which shipped a consumer a
# clean plan and zero alarms.

locals {
  # Declared extensions. Values are homogeneous (strings and lists of strings)
  # so the map can be iterated — the per-extension config itself is resolved
  # separately below, because its shape differs per extension.
  #
  #   parse         structural | resolved — WHICH SAM parse the config is read
  #                 from. Structural reads are always plan-known but resolve
  #                 parameters to their template Default unless the parameter is
  #                 named in var.structural_sam_parameters; resolved reads see
  #                 the caller's real values but can be unknown at plan.
  #   since_version First release implementing the extension, for documentation
  #                 only. It CANNOT drive diagnostics: a module cannot know
  #                 about extensions added after it was cut, so it can never
  #                 report "introduced in a later version" for a key it has
  #                 never heard of.
  extension_registry = {
    Alarms = {
      sam_key        = "Metadata.SlsTf.Alarms"
      yaml_key       = "alarms"
      parse          = "structural"
      since_version  = "0.7.0"
      stability      = "stable"
      formats        = ["sam", "serverless"]
      implementation = "alarm-sets.tf"
    }
    Dashboard = {
      sam_key        = "Metadata.SlsTf.Dashboard"
      yaml_key       = "dashboard"
      parse          = "structural"
      since_version  = "0.8.0"
      stability      = "stable"
      formats        = ["sam", "serverless"]
      implementation = "dashboard.tf"
    }
    CustomDomain = {
      # since_version is the SAM key's arrival; the serverless-yaml form
      # (provider.customDomain) predates it and is read through the provider
      # block rather than here — see _extension_custom_domain_present.
      sam_key        = "Metadata.SlsTf.CustomDomain"
      yaml_key       = "provider.customDomain"
      parse          = "resolved"
      since_version  = "0.10.0"
      stability      = "stable"
      formats        = ["sam", "serverless"]
      implementation = "http-api-domain.tf"
    }
  }

  # --------------------------------------------------------------------------
  # Per-extension resolution
  # --------------------------------------------------------------------------
  # Each extension resolves to a JSON STRING, not a value. Two reasons:
  #
  #  1. The "absent" value differs per extension ({} for Alarms, null for
  #     Dashboard/CustomDomain) and the SAM and yaml branches have different
  #     object types. Encoding inside each branch keeps both sides of every
  #     conditional a string, which is the same laundering idiom parsed_config
  #     already uses; decoding at the use site restores the value.
  #  2. Presence can then be tested by string comparison, which is always known
  #     at plan even when the underlying value is not.
  #
  # These are SEPARATE local values rather than fields of one map because
  # Terraform tracks dependencies per local value. sam-parser.tf reads
  # _extension_custom_domain_json to assemble parsed_config, while the Alarms
  # and Dashboard resolutions read parsed_config for their serverless-yaml
  # branch. As one local that is a dependency cycle; split, it is a DAG.

  # NOTE the jsonencode() placement: INSIDE each branch, so every branch of
  # every conditional is a string. Encoding outside the conditional — as these
  # lookups did before the registry — leaves Terraform unifying the two branch
  # types, and `object with 2 attributes` does not unify with `{}`:
  #
  #   Error: Inconsistent conditional result types
  #     The 'true' value includes object attribute "defaults", which is absent
  #     in the 'false' value.
  #
  # That aborted the plan for any SAM template with a non-empty
  # Metadata.SlsTf.Alarms. No fixture had one, so it shipped in v0.7.0 and
  # survived to v0.10.0 unnoticed. Keep the encode inside the branches.
  _extension_alarms_json = (
    var.config_format == "sam"
    ? (local.sam_structure != null ? jsonencode(try(local.sam_structure.Metadata.SlsTf.Alarms, {})) : "{}")
    : jsonencode(try(local.parsed_config.alarms, {}))
  )

  _extension_dashboard_json = (
    var.config_format == "sam"
    ? (local.sam_structure != null ? jsonencode(try(local.sam_structure.Metadata.SlsTf.Dashboard, null)) : "null")
    : jsonencode(try(local.parsed_config.dashboard, null))
  )

  # SAM only. The serverless-yaml form is provider.customDomain, which
  # sam-parser.tf/locals.tf assemble into provider_with_defaults; reading that
  # here would close the cycle described above. The yaml side moves under
  # custom.slsTf in a later step (docs/EXTENSIONS.md migration step 4).
  _extension_custom_domain_json = (
    var.config_format == "sam"
    ? jsonencode(try(local.sam_raw.Metadata.SlsTf.CustomDomain, null))
    : jsonencode(null)
  )

  # Registry-facing surface. Use this at extension implementation sites.
  extension_config_json = {
    Alarms       = local._extension_alarms_json
    Dashboard    = local._extension_dashboard_json
    CustomDomain = local._extension_custom_domain_json
  }

  # --------------------------------------------------------------------------
  # What is active
  # --------------------------------------------------------------------------
  # An extension is active if and only if its config is present. There is no
  # per-extension enable flag: a boolean that must agree with the config is a
  # second place for the config to be wrong, and it always fails silently in the
  # same direction (config written, flag unset, nothing created, clean plan).
  #
  # Presence is a string comparison against the encoded absent-values, so it
  # stays known at plan even when the config itself is not.
  _extension_present_encoded = {
    for name, json in local.extension_config_json :
    name => !contains(["null", "{}", "\"\""], json)
  }

  # CustomDomain in serverless yaml arrives via the provider block, so its
  # presence cannot be read off _extension_custom_domain_json (which is SAM-only
  # to avoid the dependency cycle). provider_with_defaults is downstream of
  # parsed_config and only feeds the output, so reading it here is safe.
  _extension_custom_domain_present = (
    var.config_format == "sam"
    ? local._extension_present_encoded.CustomDomain
    : try(local.provider_with_defaults.customDomain, null) != null
  )

  _extension_present = merge(
    local._extension_present_encoded,
    { CustomDomain = local._extension_custom_domain_present }
  )

  extensions_active = {
    for name, meta in local.extension_registry :
    name => {
      since     = meta.since_version
      stability = meta.stability
      parse     = meta.parse
      source    = var.config_format == "sam" ? meta.sam_key : meta.yaml_key
    }
    if local._extension_present[name]
  }
}
