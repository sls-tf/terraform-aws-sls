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
      yaml_key       = "custom.slsTf.alarms"
      legacy_yaml    = "alarms"
      parse          = "structural"
      since_version  = "0.7.0"
      stability      = "stable"
      formats        = ["sam", "serverless"]
      implementation = "alarm-sets.tf"
    }
    Dashboard = {
      sam_key        = "Metadata.SlsTf.Dashboard"
      yaml_key       = "custom.slsTf.dashboard"
      legacy_yaml    = "dashboard"
      parse          = "structural"
      since_version  = "0.8.0"
      stability      = "stable"
      formats        = ["sam", "serverless"]
      implementation = "dashboard.tf"
    }
    CustomDomain = {
      # since_version is the SAM key's arrival; the serverless-yaml form
      # predates it as provider.customDomain, which MOVED here in v0.11.0
      # rather than becoming an alias — it sat inside a section Serverless
      # Framework schema-validates, and the sole consumer was not yet live.
      sam_key        = "Metadata.SlsTf.CustomDomain"
      yaml_key       = "custom.slsTf.customDomain"
      legacy_yaml    = ""
      parse          = "resolved"
      since_version  = "0.10.0"
      stability      = "stable"
      formats        = ["sam", "serverless"]
      implementation = "http-api-domain.tf"
    }
  }

  # Extension names, for iteration and for diagnostics that list what this
  # version supports.
  extension_names = sort(keys(local.extension_registry))

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
  # _extension_custom_domain_sam_json to assemble parsed_config, while the
  # Alarms and Dashboard resolutions read parsed_config for their
  # serverless-yaml branch. As one local that is a dependency cycle; split, it
  # is a DAG.

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
  #
  # The serverless-yaml namespace is `custom.slsTf.*`, mirroring
  # `Metadata.SlsTf.*` by MECHANISM: `custom:` is the section Serverless
  # Framework leaves unvalidated, exactly as `Metadata` is the section
  # CloudFormation ignores. A bare top-level `slsTf:` would mirror the visual
  # position instead, and SF flags unknown root keys (a warning by default, a
  # hard failure under configValidationMode: error).
  #
  # The pre-namespace top-level keys stay accepted PERMANENTLY, not as a
  # deprecation with a removal date — event-service parity is why alarm sets
  # exist. Namespaced wins where both appear, but that combination is also a
  # validation error, so the precedence never silently decides anything.
  _extension_alarms_json = (
    var.config_format == "sam"
    ? (local.sam_structure != null ? jsonencode(try(local.sam_structure.Metadata.SlsTf.Alarms, {})) : "{}")
    : jsonencode(try(local.parsed_config.custom.slsTf.alarms, local.parsed_config.alarms, {}))
  )

  _extension_dashboard_json = (
    var.config_format == "sam"
    ? (local.sam_structure != null ? jsonencode(try(local.sam_structure.Metadata.SlsTf.Dashboard, null)) : "null")
    : jsonencode(try(local.parsed_config.custom.slsTf.dashboard, local.parsed_config.dashboard, null))
  )

  # SAM-only, and deliberately separate from _extension_custom_domain_json
  # below: sam-parser.tf reads THIS one to assemble parsed_config, so it must
  # not depend on parsed_config. The general local does, via the yaml branch.
  _extension_custom_domain_sam_json = (
    var.config_format == "sam"
    ? jsonencode(try(local.sam_raw.Metadata.SlsTf.CustomDomain, null))
    : "null"
  )

  # Read from parsed_config_RESOLVED so ${self:}/${env:} references inside the
  # domain config still resolve — they did when this was provider.customDomain
  # (assembled into provider_with_defaults from the resolved config), and moving
  # the key must not quietly drop that.
  _extension_custom_domain_json = (
    var.config_format == "sam"
    ? local._extension_custom_domain_sam_json
    : jsonencode(try(local.parsed_config_resolved.custom.slsTf.customDomain, null))
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

  _extension_present = local._extension_present_encoded

  # --------------------------------------------------------------------------
  # Legacy top-level yaml keys
  # --------------------------------------------------------------------------
  # Which extensions are configured at their pre-namespace top-level key. Used
  # for the deprecation notice and for the both-defined error below.
  _extension_legacy_yaml_used = var.config_format == "sam" ? [] : sort([
    for name, meta in local.extension_registry :
    name
    if meta.legacy_yaml != "" && try(local.parsed_config[meta.legacy_yaml], null) != null
  ])

  _extension_namespaced_yaml_used = var.config_format == "sam" ? [] : sort([
    for name, meta in local.extension_registry :
    name
    if try(local.parsed_config.custom.slsTf[split(".", meta.yaml_key)[2]], null) != null
  ])

  # Defining an extension at both spellings is an error rather than a silent
  # precedence win — silent precedence is the failure mode this whole design
  # exists to remove.
  extension_duplicate_errors = [
    for name in local._extension_legacy_yaml_used :
    join(" ", [
      "Extension '${name}' is defined twice: at the legacy top-level key",
      "'${local.extension_registry[name].legacy_yaml}:' and at",
      "'${local.extension_registry[name].yaml_key}'.",
      "Remove one. The namespaced key is preferred; the top-level key stays",
      "supported indefinitely, but only one of them may be present."
    ])
    if contains(local._extension_namespaced_yaml_used, name)
  ]

  # --------------------------------------------------------------------------
  # Unknown keys under the namespace
  # --------------------------------------------------------------------------
  # Scoped STRICTLY to the sls.tf namespace and never to its parent. `Metadata`
  # legitimately carries AWS::CloudFormation::Interface, cfn-lint config and CDK
  # asset keys; `custom:` carries every Serverless Framework plugin's config.
  # Rejecting unknown keys there would break configs that are perfectly correct.
  #
  # can(keys(...)) guards a namespace that is present but not a map (`SlsTf:
  # "yes"`), which would otherwise abort the plan inside this diagnostic rather
  # than reporting it.
  _extension_key_to_name = {
    for name, meta in local.extension_registry :
    (var.config_format == "sam" ? element(split(".", meta.sam_key), 2) : element(split(".", meta.yaml_key), 2)) => name
  }

  _extension_namespace_path = var.config_format == "sam" ? "Metadata.SlsTf" : "custom.slsTf"

  # Only worth saying when the setting would actually change something.
  _extension_downgrade_hint = (
    var.extension_unknown_key_behaviour == "error"
    ? "Set extension_unknown_key_behaviour = \"warn\" to downgrade this to a plan-time notice."
    : ""
  )

  _extension_namespace_keys = (
    var.config_format == "sam"
    ? (can(keys(local.sam_structure.Metadata.SlsTf)) ? keys(local.sam_structure.Metadata.SlsTf) : [])
    : (can(keys(local.parsed_config.custom.slsTf)) ? keys(local.parsed_config.custom.slsTf) : [])
  )

  _extension_unknown_keys = sort([
    for k in local._extension_namespace_keys :
    k if !contains(keys(local._extension_key_to_name), k)
  ])

  # Nearest-match suggestion. HCL has no edit distance, so this catches the
  # cases that actually occur — wrong case (`alarm`/`ALARMS`) and a prefix
  # relationship (`Alarm` for `Alarms`, `CustomDomainName` for `CustomDomain`).
  _extension_key_suggestion = {
    for k in local._extension_unknown_keys :
    k => join(", ", [
      for known in sort(keys(local._extension_key_to_name)) :
      known
      if lower(known) == lower(k) || startswith(lower(known), lower(k)) || startswith(lower(k), lower(known))
    ])
  }

  extension_unknown_key_errors = [
    for k in local._extension_unknown_keys :
    join(" ", compact([
      "Unknown sls.tf extension '${k}' under ${local._extension_namespace_path}.",
      local._extension_key_suggestion[k] != "" ? "Did you mean '${local._extension_key_suggestion[k]}'?" : "",
      "Extensions supported by sls.tf v${local.module_version}:",
      "${join(", ", local.extension_names)}.",
      # A module cannot know about extensions added after it was cut, so it can
      # never say "introduced in v0.12.0" for a key it has never heard of. The
      # honest version of that diagnostic is to name the running version and
      # let the reader check whether the key is newer.
      "If '${k}' is a newer extension, this module is pinned to v${local.module_version} and does not implement it —",
      "check the CHANGELOG for the version that introduced it.",
      local._extension_downgrade_hint
    ]))
  ]

  # --------------------------------------------------------------------------
  # Misspelled namespace
  # --------------------------------------------------------------------------
  # Without this, `Metadata.Slstf.Alarms` is not "an unknown key under the
  # namespace" — it is no namespace at all, so nothing fires and the silence is
  # exactly what the unknown-key check was added to remove.
  _extension_namespace_parent_keys = (
    var.config_format == "sam"
    ? (can(keys(local.sam_structure.Metadata)) ? keys(local.sam_structure.Metadata) : [])
    : (can(keys(local.parsed_config.custom)) ? keys(local.parsed_config.custom) : [])
  )

  _extension_namespace_expected = var.config_format == "sam" ? "SlsTf" : "slsTf"

  _extension_namespace_near_misses = sort([
    for k in local._extension_namespace_parent_keys :
    k
    if lower(k) == "slstf" && k != local._extension_namespace_expected
  ])

  extension_namespace_errors = [
    for k in local._extension_namespace_near_misses :
    join(" ", compact([
      "sls.tf extension namespace is misspelled: found '${k}', expected",
      "'${local._extension_namespace_expected}' (as ${local._extension_namespace_path}).",
      "Everything under '${k}' is being ignored entirely.",
      local._extension_downgrade_hint
    ]))
  ]

  extensions_active = {
    for name, meta in local.extension_registry :
    name => {
      since     = meta.since_version
      stability = meta.stability
      parse     = meta.parse
      # Where the config was ACTUALLY read from, not the canonical spelling —
      # "did my config take effect, and which key did it come from?" is the
      # question this output exists to answer, and for a consumer with both
      # spellings in play the canonical name would be misleading.
      source = var.config_format == "sam" ? meta.sam_key : (
        contains(local._extension_legacy_yaml_used, name) ? meta.legacy_yaml : meta.yaml_key
      )
    }
    if local._extension_present[name]
  }
}

# Plan-time notice, not an error: the pre-namespace top-level keys are
# supported indefinitely, so a consumer who never moves is not broken — they
# are just told where the key now lives. Mirrors the naming-lint precedent
# (naming-lint.tf) as the module's only other warn-don't-fail check.
check "extension_legacy_yaml_keys" {
  assert {
    condition = !(var.extension_legacy_key_notice && length(local._extension_legacy_yaml_used) > 0)
    error_message = join(" ", [
      "These extensions are configured at their pre-v0.11.0 top-level keys:",
      join(", ", [
        for name in local._extension_legacy_yaml_used :
        "${local.extension_registry[name].legacy_yaml}: (now ${local.extension_registry[name].yaml_key})"
      ]),
      "— these keys still work and will keep working, but Serverless Framework",
      "flags unrecognised root keys, so prefer the namespaced form under",
      "custom.slsTf. See docs/EXTENSIONS.md."
    ])
  }
}

locals {
  # Errors that respect var.extension_unknown_key_behaviour. In "warn" mode
  # they move to the check block below instead.
  _extension_strict_errors = concat(
    local.extension_unknown_key_errors,
    local.extension_namespace_errors,
  )

  # Aggregate of every extension-level error, appended to
  # local.validation_errors (locals.tf) so extensions fail through the same
  # null_resource.config_validation gate as everything else rather than
  # inventing a second error channel.
  #
  # Duplicate-spelling errors are NOT downgradable: unlike an unknown key,
  # there is no reading under which the config is right, and picking a winner
  # silently is the failure mode being removed.
  extension_validation_errors = concat(
    local.extension_duplicate_errors,
    var.extension_unknown_key_behaviour == "error" ? local._extension_strict_errors : [],
  )
}

# The escape hatch. Every other strict behaviour in this module sits behind a
# variable with a permissive default (sam_strict_intrinsics,
# naming_convention_warning, s3_force_destroy), and a large estate needs a way
# to roll forward onto v0.11.0 without a flag day. Unlike those, this one
# defaults to STRICT: a config that was silently doing nothing should start
# failing loudly, which is the entire point of the change.
check "extension_unknown_keys" {
  assert {
    condition = !(var.extension_unknown_key_behaviour == "warn" && length(local._extension_strict_errors) > 0)
    error_message = join("\n", concat(
      ["sls.tf extension problems (downgraded to a notice by extension_unknown_key_behaviour = \"warn\"):"],
      [for e in local._extension_strict_errors : "  - ${e}"]
    ))
  }
}
